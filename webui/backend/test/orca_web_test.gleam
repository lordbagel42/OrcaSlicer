import gleam/bit_array
import gleam/string
import gleeunit
import gleeunit/should
import orca_web/moonraker
import orca_web/profiles
import orca_web/slicer

pub fn main() {
  gleeunit.main()
}

pub fn is_within_root_accepts_child_test() {
  profiles.is_within_root(
    "/app/resources/profiles",
    "/app/resources/profiles/BBL/process/fdm.json",
  )
  |> should.be_true
}

pub fn is_within_root_rejects_traversal_test() {
  profiles.is_within_root(
    "/app/resources/profiles",
    "/app/resources/profiles/../../etc/passwd.json",
  )
  |> should.be_false
}

pub fn is_within_root_rejects_outside_test() {
  profiles.is_within_root("/app/resources/profiles", "/etc/shadow.json")
  |> should.be_false
}

pub fn is_within_root_requires_json_test() {
  profiles.is_within_root(
    "/app/resources/profiles",
    "/app/resources/profiles/BBL/process/fdm.txt",
  )
  |> should.be_false
}

pub fn build_args_without_overrides_test() {
  let req =
    slicer.SliceRequest(
      job_dir: "/tmp/orca/job1",
      model_path: "/tmp/orca/job1/model.stl",
      machine_path: "/p/m.json",
      process_path: "/p/proc.json",
      filament_path: "/p/fil.json",
      overrides: [],
    )
  slicer.build_args(req, "/tmp/orca/job1/out", "")
  |> should.equal([
    "--load-settings", "/p/m.json;/p/proc.json",
    "--load-filaments", "/p/fil.json",
    "--slice", "0",
    "--outputdir", "/tmp/orca/job1/out",
    "/tmp/orca/job1/model.stl",
  ])
}

pub fn build_args_with_override_appends_file_test() {
  let req =
    slicer.SliceRequest(
      job_dir: "/tmp/orca/job1",
      model_path: "/tmp/orca/job1/model.stl",
      machine_path: "/p/m.json",
      process_path: "/p/proc.json",
      filament_path: "/p/fil.json",
      overrides: [#("layer_height", "0.16")],
    )
  let args = slicer.build_args(req, "/tmp/orca/job1/out", "/tmp/orca/job1/override.json")
  // The override profile must come *after* the base process so it wins.
  case args {
    ["--load-settings", settings, ..] ->
      settings
      |> should.equal("/p/m.json;/p/proc.json;/tmp/orca/job1/override.json")
    _ -> should.fail()
  }
}

pub fn multipart_body_has_file_and_root_test() {
  let body = moonraker.multipart_body("part.gcode", bit_array.from_string("G28\n"))
  let text = bit_array.to_string(body)

  case text {
    Ok(s) -> {
      string.contains(s, "name=\"root\"")
      |> should.be_true
      string.contains(s, "gcodes")
      |> should.be_true
      string.contains(s, "filename=\"part.gcode\"")
      |> should.be_true
      string.contains(s, "G28")
      |> should.be_true
    }
    Error(_) -> should.fail()
  }
}
