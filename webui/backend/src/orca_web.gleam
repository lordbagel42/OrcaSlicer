import envoy
import gleam/erlang/process
import gleam/int
import gleam/result
import mist
import orca_web/router.{type Context, Context}
import simplifile
import wisp
import wisp/wisp_mist

/// Reads configuration from the environment, with sensible container defaults.
fn load_context() -> Context {
  let profiles_dir =
    envoy.get("ORCA_PROFILES_DIR")
    |> result.unwrap("/app/resources/profiles")
  let orca_bin =
    envoy.get("ORCA_BIN")
    |> result.unwrap("orca-slicer")
  let work_dir =
    envoy.get("ORCA_WORK_DIR")
    |> result.unwrap("/tmp/orca")

  // Best-effort: ensure the job working directory exists.
  let _ = simplifile.create_directory_all(work_dir)

  Context(profiles_dir: profiles_dir, orca_bin: orca_bin, work_dir: work_dir)
}

pub fn main() {
  wisp.configure_logger()
  let ctx = load_context()

  let port =
    envoy.get("PORT")
    |> result.try(int.parse)
    |> result.unwrap(8080)

  let secret = wisp.random_string(64)
  let handler = fn(req) { router.handle_request(req, ctx) }

  let assert Ok(_) =
    wisp_mist.handler(handler, secret)
    |> mist.new
    |> mist.port(port)
    |> mist.bind("0.0.0.0")
    |> mist.start

  wisp.log_info("orca_web listening on port " <> int.to_string(port))
  process.sleep_forever()
}
