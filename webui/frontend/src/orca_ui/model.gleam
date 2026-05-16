import gleam/option.{type Option}

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

pub type UploadResp {
  UploadResp(job_id: String, filename: String, ext: String, url: String)
}

pub type SliceResp {
  SliceResp(ok: Bool, gcode_file: String, gcode_url: String, log: String)
}

/// One curated, human-editable slicing setting. Empty value => leave the
/// profile default untouched (only non-empty values become CLI overrides).
pub type Setting {
  Setting(key: String, label: String, value: String)
}

pub fn default_settings() -> List(Setting) {
  [
    Setting("layer_height", "Layer height (mm)", ""),
    Setting("initial_layer_print_height", "First layer height (mm)", ""),
    Setting("wall_loops", "Wall loops", ""),
    Setting("sparse_infill_density", "Infill density (e.g. 15%)", ""),
    Setting("sparse_infill_pattern", "Infill pattern", ""),
    Setting("top_shell_layers", "Top shell layers", ""),
    Setting("bottom_shell_layers", "Bottom shell layers", ""),
    Setting("support_type", "Support type (e.g. tree(auto))", ""),
    Setting("brim_type", "Brim type", ""),
  ]
}

pub type Model {
  Model(
    status: String,
    job_id: Option(String),
    model_url: Option(String),
    model_ext: String,
    profiles: Option(Profiles),
    sel_machine: String,
    sel_process: String,
    sel_filament: String,
    settings: List(Setting),
    raw_overrides: String,
    slicing: Bool,
    slice_log: String,
    gcode_url: Option(String),
    gcode_file: Option(String),
    printer_url: String,
    printer_key: String,
    start_print: Bool,
    sending: Bool,
    send_status: String,
  )
}

pub fn init_model() -> Model {
  Model(
    status: "Loading profiles…",
    job_id: option.None,
    model_url: option.None,
    model_ext: "",
    profiles: option.None,
    sel_machine: "",
    sel_process: "",
    sel_filament: "",
    settings: default_settings(),
    raw_overrides: "",
    slicing: False,
    slice_log: "",
    gcode_url: option.None,
    gcode_file: option.None,
    printer_url: "",
    printer_key: "",
    start_print: False,
    sending: False,
    send_status: "",
  )
}

pub type Msg {
  ClickedUpload
  UploadCompleted(Result(UploadResp, String))
  ProfilesLoaded(Result(Profiles, String))
  SelectedMachine(String)
  SelectedProcess(String)
  SelectedFilament(String)
  SettingChanged(String, String)
  RawOverridesChanged(String)
  ClickedSlice
  SliceCompleted(Result(SliceResp, String))
  PrinterUrlChanged(String)
  PrinterKeyChanged(String)
  ToggledStartPrint(Bool)
  ClickedSend
  SendCompleted(Result(String, String))
}
