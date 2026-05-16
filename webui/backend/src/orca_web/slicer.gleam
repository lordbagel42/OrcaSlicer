//// Wraps the headless OrcaSlicer CLI.
////
//// Settings precedence (from src/OrcaSlicer.cpp:7194): command line >
//// --load-settings/--load-filaments files (later files override earlier) >
//// settings embedded in a 3MF. We exploit the "later overrides earlier" rule:
//// user tweaks are written to a small override JSON appended after the base
//// process profile, so we never have to merge JSON ourselves.

import gleam/json
import gleam/list
import gleam/result
import gleam/string
import shellout
import simplifile

pub type SliceRequest {
  SliceRequest(
    job_dir: String,
    model_path: String,
    machine_path: String,
    process_path: String,
    filament_path: String,
    overrides: List(#(String, String)),
  )
}

pub type SliceResult {
  SliceResult(gcode_path: String, log: String)
}

pub type SliceError {
  CliFailed(exit_code: Int, log: String)
  NoGcodeProduced(log: String)
  IoError(String)
}

/// Write the user's overridden keys as a minimal process profile that the CLI
/// loads *after* the base profile so its values win.
fn write_override_file(
  job_dir: String,
  overrides: List(#(String, String)),
) -> Result(String, SliceError) {
  case overrides {
    [] -> Ok("")
    pairs -> {
      let fields =
        list.append(
          [
            #("type", json.string("process")),
            #("name", json.string("web_override")),
          ],
          list.map(pairs, fn(p) { #(p.0, json.string(p.1)) }),
        )
      let path = job_dir <> "/override.json"
      case simplifile.write(path, json.to_string(json.object(fields))) {
        Ok(_) -> Ok(path)
        Error(e) -> Error(IoError(simplifile.describe_error(e)))
      }
    }
  }
}

fn settings_arg(
  machine: String,
  process: String,
  override_path: String,
) -> String {
  case override_path {
    "" -> machine <> ";" <> process
    p -> machine <> ";" <> process <> ";" <> p
  }
}

fn find_gcode(out_dir: String) -> Result(String, SliceError) {
  case simplifile.read_directory(out_dir) {
    Error(e) -> Error(IoError(simplifile.describe_error(e)))
    Ok(entries) ->
      case
        list.find(entries, fn(f) {
          string.ends_with(f, ".gcode") || string.ends_with(f, ".gcode.3mf")
        })
      {
        Ok(file) -> Ok(out_dir <> "/" <> file)
        Error(_) -> Error(NoGcodeProduced(""))
      }
  }
}

/// Build the CLI argument vector. Pure — unit tested directly.
pub fn build_args(
  req: SliceRequest,
  out_dir: String,
  override_path: String,
) -> List(String) {
  [
    "--load-settings",
    settings_arg(req.machine_path, req.process_path, override_path),
    "--load-filaments",
    req.filament_path,
    "--slice",
    "0",
    "--outputdir",
    out_dir,
    req.model_path,
  ]
}

pub fn run(orca_bin: String, req: SliceRequest) -> Result(SliceResult, SliceError) {
  let out_dir = req.job_dir <> "/out"
  use _ <- result.try(
    simplifile.create_directory_all(out_dir)
    |> result.map_error(fn(e) { IoError(simplifile.describe_error(e)) }),
  )
  use override_path <- result.try(write_override_file(
    req.job_dir,
    req.overrides,
  ))
  let args = build_args(req, out_dir, override_path)

  case shellout.command(run: orca_bin, with: args, in: req.job_dir, opt: []) {
    Ok(log) ->
      find_gcode(out_dir)
      |> result.map(fn(path) { SliceResult(gcode_path: path, log: log) })
      |> result.map_error(fn(e) {
        case e {
          NoGcodeProduced(_) -> NoGcodeProduced(log)
          other -> other
        }
      })
    Error(#(code, log)) -> Error(CliFailed(exit_code: code, log: log))
  }
}
