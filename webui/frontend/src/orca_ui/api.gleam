import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import lustre/effect.{type Effect}
import lustre_http
import orca_ui/model.{
  type Msg, type Profiles, type SliceResp, type UploadResp, ProfileRef, Profiles,
  ProfilesLoaded, SendCompleted, SliceCompleted, SliceResp, UploadCompleted,
  UploadResp,
}

fn http_err(e: lustre_http.HttpError) -> String {
  case e {
    lustre_http.NotFound -> "not found"
    lustre_http.InternalServerError(m) -> m
    lustre_http.OtherError(code, m) ->
      "http " <> int.to_string(code) <> ": " <> m
    lustre_http.BadUrl(u) -> "bad url: " <> u
    lustre_http.NetworkError -> "network error — is the backend running?"
    lustre_http.Unauthorized -> "unauthorized"
    lustre_http.JsonError(_) -> "invalid response from server"
  }
}

// --- profiles --------------------------------------------------------------

fn ref_decoder() -> decode.Decoder(model.ProfileRef) {
  use vendor <- decode.field("vendor", decode.string)
  use name <- decode.field("name", decode.string)
  use path <- decode.field("path", decode.string)
  decode.success(ProfileRef(vendor:, name:, path:))
}

fn profiles_decoder() -> decode.Decoder(Profiles) {
  use machines <- decode.field("machines", decode.list(ref_decoder()))
  use processes <- decode.field("processes", decode.list(ref_decoder()))
  use filaments <- decode.field("filaments", decode.list(ref_decoder()))
  decode.success(Profiles(machines:, processes:, filaments:))
}

pub fn load_profiles() -> Effect(Msg) {
  lustre_http.get(
    "/api/profiles",
    lustre_http.expect_json(profiles_decoder(), fn(res) {
      ProfilesLoaded(result.map_error(res, http_err))
    }),
  )
}

// --- slice -----------------------------------------------------------------

fn slice_decoder() -> decode.Decoder(SliceResp) {
  use ok <- decode.field("ok", decode.bool)
  use gcode_file <- decode.optional_field("gcode_file", "", decode.string)
  use gcode_url <- decode.optional_field("gcode_url", "", decode.string)
  use log <- decode.optional_field("log", "", decode.string)
  decode.success(SliceResp(ok:, gcode_file:, gcode_url:, log:))
}

pub fn slice(
  job_id: String,
  machine: String,
  process: String,
  filament: String,
  overrides: List(#(String, String)),
) -> Effect(Msg) {
  let body =
    json.object([
      #("job_id", json.string(job_id)),
      #("machine_path", json.string(machine)),
      #("process_path", json.string(process)),
      #("filament_path", json.string(filament)),
      #(
        "overrides",
        json.object(list.map(overrides, fn(p) { #(p.0, json.string(p.1)) })),
      ),
    ])
  lustre_http.post(
    "/api/slice",
    body,
    lustre_http.expect_json(slice_decoder(), fn(res) {
      SliceCompleted(result.map_error(res, http_err))
    }),
  )
}

// --- send to printer -------------------------------------------------------

fn send_decoder() -> decode.Decoder(String) {
  use message <- decode.optional_field("message", "sent", decode.string)
  decode.success(message)
}

pub fn send_to_printer(
  job_id: String,
  gcode_file: String,
  base_url: String,
  api_key: String,
  start_print: Bool,
) -> Effect(Msg) {
  let body =
    json.object([
      #("job_id", json.string(job_id)),
      #("gcode_file", json.string(gcode_file)),
      #("base_url", json.string(base_url)),
      #("api_key", json.string(api_key)),
      #("start_print", json.bool(start_print)),
    ])
  lustre_http.post(
    "/api/send-to-printer",
    body,
    lustre_http.expect_json(send_decoder(), fn(res) {
      SendCompleted(result.map_error(res, http_err))
    }),
  )
}

// --- model upload (multipart, via FFI fetch) -------------------------------

@external(javascript, "../viewer.ffi.mjs", "uploadModel")
fn do_upload(
  url: String,
  on_ok: fn(String) -> Nil,
  on_err: fn(String) -> Nil,
) -> Nil

fn upload_decoder() -> decode.Decoder(UploadResp) {
  use job_id <- decode.field("job_id", decode.string)
  use filename <- decode.field("filename", decode.string)
  use ext <- decode.field("ext", decode.string)
  use url <- decode.field("url", decode.string)
  decode.success(UploadResp(job_id:, filename:, ext:, url:))
}

pub fn upload_model() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    do_upload(
      "/api/upload",
      fn(text) {
        case json.parse(text, upload_decoder()) {
          Ok(r) -> dispatch(UploadCompleted(Ok(r)))
          Error(_) -> dispatch(UploadCompleted(Error("bad upload response")))
        }
      },
      fn(err) { dispatch(UploadCompleted(Error(err))) },
    )
  })
}
