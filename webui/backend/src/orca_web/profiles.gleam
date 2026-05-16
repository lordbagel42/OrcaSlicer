//// Reads the OrcaSlicer JSON profile tree shipped under
//// `resources/profiles/<Vendor>/{machine,process,filament}/*.json`.
//// Profiles are read as-is — never duplicated or rewritten here.

import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile

pub type ProfileRef {
  ProfileRef(vendor: String, name: String, path: String)
}

pub type Profiles {
  Profiles(
    machines: List(ProfileRef),
    processes: List(ProfileRef),
    filaments: List(ProfileRef),
  )
}

pub type Error {
  NotFound
  ReadError(String)
}

fn json_files(dir: String) -> List(String) {
  case simplifile.read_directory(dir) {
    Ok(entries) ->
      entries
      |> list.filter(string.ends_with(_, ".json"))
    Error(_) -> []
  }
}

fn refs_in(vendor: String, root: String, kind: String) -> List(ProfileRef) {
  let dir = root <> "/" <> vendor <> "/" <> kind
  json_files(dir)
  |> list.map(fn(file) {
    let name = string.replace(file, ".json", "")
    ProfileRef(vendor: vendor, name: name, path: dir <> "/" <> file)
  })
}

fn vendor_dirs(root: String) -> List(String) {
  case simplifile.read_directory(root) {
    Error(_) -> []
    Ok(entries) ->
      entries
      |> list.filter(fn(entry) {
        case simplifile.is_directory(root <> "/" <> entry) {
          Ok(is_dir) -> is_dir
          Error(_) -> False
        }
      })
  }
}

/// Scan the whole profile tree into grouped lists.
pub fn scan(root: String) -> Profiles {
  let vendors = vendor_dirs(root)
  let collect = fn(kind) {
    vendors
    |> list.flat_map(refs_in(_, root, kind))
  }
  Profiles(
    machines: collect("machine"),
    processes: collect("process"),
    filaments: collect("filament"),
  )
}

fn ref_to_json(ref: ProfileRef) -> json.Json {
  json.object([
    #("vendor", json.string(ref.vendor)),
    #("name", json.string(ref.name)),
    #("path", json.string(ref.path)),
  ])
}

pub fn to_json(profiles: Profiles) -> json.Json {
  json.object([
    #("machines", json.array(profiles.machines, ref_to_json)),
    #("processes", json.array(profiles.processes, ref_to_json)),
    #("filaments", json.array(profiles.filaments, ref_to_json)),
  ])
}

/// Locate a single process profile file by vendor + name and return its raw
/// JSON text, so the frontend can render an editable settings form from it.
pub fn read_process(
  root: String,
  vendor: String,
  name: String,
) -> Result(String, Error) {
  let path = root <> "/" <> vendor <> "/process/" <> name <> ".json"
  case simplifile.read(path) {
    Ok(content) -> Ok(content)
    Error(simplifile.Enoent) -> Error(NotFound)
    Error(e) -> Error(ReadError(simplifile.describe_error(e)))
  }
}

/// Validate that a caller-supplied profile path stays inside the profile root
/// (defense against path traversal in the slice request).
pub fn is_within_root(root: String, path: String) -> Bool {
  string.starts_with(path, root <> "/")
  && !string.contains(path, "..")
  && string.ends_with(path, ".json")
}

/// Helper used by tests and the router to fail fast on a missing root.
pub fn ensure_root(root: String) -> Result(Nil, Error) {
  case simplifile.is_directory(root) {
    Ok(True) -> Ok(Nil)
    _ -> Error(ReadError("profiles root not found: " <> root))
  }
}
