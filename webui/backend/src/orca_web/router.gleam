//// HTTP routing for the OrcaSlicer web backend.

import gleam/dict
import gleam/dynamic/decode
import gleam/http
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import orca_web/moonraker
import orca_web/profiles
import orca_web/slicer
import simplifile
import wisp.{type Request, type Response}

pub type Context {
  Context(profiles_dir: String, orca_bin: String, work_dir: String)
}

// --- helpers ---------------------------------------------------------------

fn json_resp(status: Int, body: json.Json) -> Response {
  wisp.response(status)
  |> wisp.set_header("content-type", "application/json")
  |> wisp.string_body(json.to_string(body))
}

fn error_json(status: Int, message: String) -> Response {
  json_resp(status, json.object([#("error", json.string(message))]))
}

/// Keep only filesystem-safe characters — guards every job id we accept from
/// a client against path traversal.
fn safe_id(raw: String) -> String {
  raw
  |> string.to_graphemes
  |> list.filter(fn(c) {
    case c {
      "/" | "\\" | "." | " " -> False
      _ -> True
    }
  })
  |> string.concat
}

fn job_dir(ctx: Context, job_id: String) -> String {
  ctx.work_dir <> "/" <> safe_id(job_id)
}

fn extension(filename: String) -> String {
  case string.split(filename, ".") {
    [] -> ""
    parts ->
      case list.last(parts) {
        Ok(ext) -> "." <> string.lowercase(ext)
        Error(_) -> ""
      }
  }
}

fn model_in(dir: String) -> Result(String, Nil) {
  case simplifile.read_directory(dir) {
    Error(_) -> Error(Nil)
    Ok(entries) ->
      list.find(entries, string.starts_with(_, "model."))
      |> result.map(fn(f) { dir <> "/" <> f })
  }
}

fn cors(resp: Response) -> Response {
  resp
  |> wisp.set_header("access-control-allow-origin", "*")
  |> wisp.set_header("access-control-allow-headers", "content-type")
  |> wisp.set_header("access-control-allow-methods", "GET, POST, OPTIONS")
}

// --- request decoders ------------------------------------------------------

type SliceBody {
  SliceBody(
    job_id: String,
    machine_path: String,
    process_path: String,
    filament_path: String,
    overrides: List(#(String, String)),
  )
}

fn slice_decoder() -> decode.Decoder(SliceBody) {
  use job_id <- decode.field("job_id", decode.string)
  use machine_path <- decode.field("machine_path", decode.string)
  use process_path <- decode.field("process_path", decode.string)
  use filament_path <- decode.field("filament_path", decode.string)
  use overrides <- decode.optional_field(
    "overrides",
    dict.new(),
    decode.dict(decode.string, decode.string),
  )
  decode.success(SliceBody(
    job_id:,
    machine_path:,
    process_path:,
    filament_path:,
    overrides: dict.to_list(overrides),
  ))
}

type SendBody {
  SendBody(
    job_id: String,
    gcode_file: String,
    base_url: String,
    api_key: String,
    filename: String,
    start_print: Bool,
  )
}

fn send_decoder() -> decode.Decoder(SendBody) {
  use job_id <- decode.field("job_id", decode.string)
  use gcode_file <- decode.field("gcode_file", decode.string)
  use base_url <- decode.field("base_url", decode.string)
  use api_key <- decode.optional_field("api_key", "", decode.string)
  use filename <- decode.optional_field("filename", "", decode.string)
  use start_print <- decode.optional_field("start_print", False, decode.bool)
  decode.success(SendBody(
    job_id:,
    gcode_file:,
    base_url:,
    api_key:,
    filename:,
    start_print:,
  ))
}

// --- routing ---------------------------------------------------------------

pub fn handle_request(req: Request, ctx: Context) -> Response {
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  // Static job artefacts (uploaded model + sliced g-code) served from work_dir,
  // so the browser viewer/download use plain URLs and we never hand-roll
  // binary response bodies.
  use <- wisp.serve_static(req, under: "/files", from: ctx.work_dir)

  case wisp.method(req) {
    http.Options -> cors(wisp.response(204))
    _ -> route(req, ctx) |> cors
  }
}

fn route(req: Request, ctx: Context) -> Response {
  case wisp.path_segments(req) {
    ["api", "health"] -> json_resp(200, json.object([#("status", json.string("ok"))]))

    ["api", "profiles"] -> handle_profiles(ctx)

    ["api", "profiles", "process", vendor, name] ->
      handle_process(ctx, vendor, name)

    ["api", "upload"] -> handle_upload(req, ctx)

    ["api", "slice"] -> handle_slice(req, ctx)

    ["api", "send-to-printer"] -> handle_send(req, ctx)

    _ -> error_json(404, "not found")
  }
}

fn handle_profiles(ctx: Context) -> Response {
  case profiles.ensure_root(ctx.profiles_dir) {
    Error(_) -> error_json(500, "profiles directory unavailable")
    Ok(_) ->
      profiles.scan(ctx.profiles_dir)
      |> profiles.to_json
      |> json_resp(200, _)
  }
}

fn handle_process(ctx: Context, vendor: String, name: String) -> Response {
  case profiles.read_process(ctx.profiles_dir, vendor, name) {
    Ok(raw) ->
      wisp.response(200)
      |> wisp.set_header("content-type", "application/json")
      |> wisp.string_body(raw)
    Error(profiles.NotFound) -> error_json(404, "process profile not found")
    Error(profiles.ReadError(m)) -> error_json(500, m)
  }
}

fn handle_upload(req: Request, ctx: Context) -> Response {
  use <- wisp.require_method(req, http.Post)
  use formdata <- wisp.require_form(req)

  case formdata.files {
    [#(_, uploaded), ..] -> {
      let job = wisp.random_string(20) |> safe_id
      let dir = job_dir(ctx, job)
      let ext = extension(uploaded.file_name)
      let dest = dir <> "/model" <> ext

      let outcome = {
        use _ <- result.try(simplifile.create_directory_all(dir))
        simplifile.copy_file(uploaded.path, dest)
      }
      case outcome {
        Ok(_) ->
          json_resp(
            200,
            json.object([
              #("job_id", json.string(job)),
              #("filename", json.string("model" <> ext)),
              #("ext", json.string(ext)),
              #("url", json.string("/files/" <> job <> "/model" <> ext)),
            ]),
          )
        Error(e) -> error_json(500, simplifile.describe_error(e))
      }
    }
    [] -> error_json(400, "no file in upload")
  }
}

fn handle_slice(req: Request, ctx: Context) -> Response {
  use <- wisp.require_method(req, http.Post)
  use body <- wisp.require_json(req)

  case decode.run(body, slice_decoder()) {
    Error(_) -> error_json(400, "invalid slice request body")
    Ok(b) -> {
      let dir = job_dir(ctx, b.job_id)
      let paths_ok =
        profiles.is_within_root(ctx.profiles_dir, b.machine_path)
        && profiles.is_within_root(ctx.profiles_dir, b.process_path)
        && profiles.is_within_root(ctx.profiles_dir, b.filament_path)
      case paths_ok, model_in(dir) {
        False, _ -> error_json(400, "profile paths must be inside the profile root")
        True, Error(_) -> error_json(404, "model not found for job — upload first")
        True, Ok(model) -> run_slice(ctx, b, dir, model)
      }
    }
  }
}

fn run_slice(
  ctx: Context,
  b: SliceBody,
  dir: String,
  model: String,
) -> Response {
  let sr =
    slicer.SliceRequest(
      job_dir: dir,
      model_path: model,
      machine_path: b.machine_path,
      process_path: b.process_path,
      filament_path: b.filament_path,
      overrides: b.overrides,
    )
  case slicer.run(ctx.orca_bin, sr) {
    Ok(res) -> {
      let file = case string.split(res.gcode_path, "/") {
        parts -> list.last(parts) |> result.unwrap("output.gcode")
      }
      json_resp(
        200,
        json.object([
          #("ok", json.bool(True)),
          #("gcode_file", json.string(file)),
          #(
            "gcode_url",
            json.string("/files/" <> safe_id(b.job_id) <> "/out/" <> file),
          ),
          #("log", json.string(res.log)),
        ]),
      )
    }
    Error(slicer.CliFailed(code, log)) ->
      json_resp(
        422,
        json.object([
          #("ok", json.bool(False)),
          #("error", json.string("slicer exited with code " <> string.inspect(code))),
          #("log", json.string(log)),
        ]),
      )
    Error(slicer.NoGcodeProduced(log)) ->
      json_resp(
        422,
        json.object([
          #("ok", json.bool(False)),
          #("error", json.string("no g-code produced")),
          #("log", json.string(log)),
        ]),
      )
    Error(slicer.IoError(m)) -> error_json(500, m)
  }
}

fn handle_send(req: Request, ctx: Context) -> Response {
  use <- wisp.require_method(req, http.Post)
  use body <- wisp.require_json(req)

  case decode.run(body, send_decoder()) {
    Error(_) -> error_json(400, "invalid send-to-printer request body")
    Ok(b) -> {
      let dir = job_dir(ctx, b.job_id)
      let gcode_path = dir <> "/out/" <> safe_id(b.gcode_file)
      let upload_name = case b.filename {
        "" -> b.gcode_file
        n -> n
      }
      let send_req =
        moonraker.SendRequest(
          base_url: b.base_url,
          api_key: b.api_key,
          gcode_path: gcode_path,
          filename: upload_name,
          start_print: b.start_print,
        )
      case moonraker.send(send_req) {
        Ok(msg) ->
          json_resp(
            200,
            json.object([
              #("ok", json.bool(True)),
              #("message", json.string(msg)),
            ]),
          )
        Error(e) ->
          json_resp(
            502,
            json.object([
              #("ok", json.bool(False)),
              #("error", json.string(moonraker.describe(e))),
            ]),
          )
      }
    }
  }
}
