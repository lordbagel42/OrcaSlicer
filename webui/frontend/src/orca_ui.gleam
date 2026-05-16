import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre
import lustre/attribute.{attribute} as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element, element, none, text}
import lustre/element/html
import lustre/event
import orca_ui/api
import orca_ui/model.{
  type Model, type Msg, type Setting, ClickedSend, ClickedSlice, ClickedUpload,
  PrinterKeyChanged, PrinterUrlChanged, ProfilesLoaded, RawOverridesChanged,
  SelectedFilament, SelectedMachine, SelectedProcess, SendCompleted, Setting,
  SettingChanged, SliceCompleted, ToggledStartPrint, UploadCompleted,
}

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
}

fn init(_flags) -> #(Model, Effect(Msg)) {
  #(model.init_model(), api.load_profiles())
}

// --- overrides assembly ----------------------------------------------------

fn parse_raw(raw: String) -> List(#(String, String)) {
  raw
  |> string.split("\n")
  |> list.filter_map(fn(line) {
    case string.split_once(line, "=") {
      Ok(#(k, v)) ->
        case string.trim(k) {
          "" -> Error(Nil)
          key -> Ok(#(key, string.trim(v)))
        }
      Error(_) -> Error(Nil)
    }
  })
}

fn collect_overrides(m: Model) -> List(#(String, String)) {
  let from_form =
    m.settings
    |> list.filter_map(fn(s: Setting) {
      case string.trim(s.value) {
        "" -> Error(Nil)
        v -> Ok(#(s.key, v))
      }
    })
  list.append(from_form, parse_raw(m.raw_overrides))
}

fn set_setting(
  settings: List(Setting),
  key: String,
  value: String,
) -> List(Setting) {
  list.map(settings, fn(s) {
    case s.key == key {
      True -> Setting(..s, value: value)
      False -> s
    }
  })
}

// --- update ----------------------------------------------------------------

fn update(m: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ClickedUpload -> #(
      model.Model(..m, status: "Uploading model…"),
      api.upload_model(),
    )

    UploadCompleted(Ok(r)) -> #(
      model.Model(
        ..m,
        job_id: Some(r.job_id),
        model_url: Some(r.url),
        model_ext: r.ext,
        status: "Model uploaded: " <> r.filename,
      ),
      effect.none(),
    )

    UploadCompleted(Error(e)) -> #(
      model.Model(..m, status: "Upload failed: " <> e),
      effect.none(),
    )

    ProfilesLoaded(Ok(p)) -> #(
      model.Model(..m, profiles: Some(p), status: "Ready — upload a model"),
      effect.none(),
    )

    ProfilesLoaded(Error(e)) -> #(
      model.Model(..m, status: "Could not load profiles: " <> e),
      effect.none(),
    )

    SelectedMachine(v) -> #(model.Model(..m, sel_machine: v), effect.none())
    SelectedProcess(v) -> #(model.Model(..m, sel_process: v), effect.none())
    SelectedFilament(v) -> #(model.Model(..m, sel_filament: v), effect.none())

    SettingChanged(key, value) -> #(
      model.Model(..m, settings: set_setting(m.settings, key, value)),
      effect.none(),
    )

    RawOverridesChanged(v) -> #(
      model.Model(..m, raw_overrides: v),
      effect.none(),
    )

    ClickedSlice ->
      case m.job_id {
        None -> #(
          model.Model(..m, status: "Upload a model first"),
          effect.none(),
        )
        Some(job) ->
          case m.sel_machine, m.sel_process, m.sel_filament {
            "", _, _ | _, "", _ | _, _, "" -> #(
              model.Model(
                ..m,
                status: "Select a printer, process and filament",
              ),
              effect.none(),
            )
            machine, process, filament -> #(
              model.Model(
                ..m,
                slicing: True,
                slice_log: "",
                gcode_url: None,
                status: "Slicing…",
              ),
              api.slice(
                job,
                machine,
                process,
                filament,
                collect_overrides(m),
              ),
            )
          }
      }

    SliceCompleted(Ok(r)) ->
      case r.ok {
        True -> #(
          model.Model(
            ..m,
            slicing: False,
            slice_log: r.log,
            gcode_url: Some(r.gcode_url),
            gcode_file: Some(r.gcode_file),
            status: "Slice complete",
          ),
          effect.none(),
        )
        False -> #(
          model.Model(
            ..m,
            slicing: False,
            slice_log: r.log,
            status: "Slice failed",
          ),
          effect.none(),
        )
      }

    SliceCompleted(Error(e)) -> #(
      model.Model(..m, slicing: False, status: "Slice failed: " <> e),
      effect.none(),
    )

    PrinterUrlChanged(v) -> #(model.Model(..m, printer_url: v), effect.none())
    PrinterKeyChanged(v) -> #(model.Model(..m, printer_key: v), effect.none())
    ToggledStartPrint(v) -> #(
      model.Model(..m, start_print: v),
      effect.none(),
    )

    ClickedSend ->
      case m.job_id, m.gcode_file {
        Some(job), Some(file) ->
          case string.trim(m.printer_url) {
            "" -> #(
              model.Model(..m, send_status: "Enter the Moonraker URL"),
              effect.none(),
            )
            url -> #(
              model.Model(..m, sending: True, send_status: "Sending…"),
              api.send_to_printer(
                job,
                file,
                url,
                m.printer_key,
                m.start_print,
              ),
            )
          }
        _, _ -> #(
          model.Model(..m, send_status: "Slice something first"),
          effect.none(),
        )
      }

    SendCompleted(Ok(msg_text)) -> #(
      model.Model(..m, sending: False, send_status: msg_text),
      effect.none(),
    )
    SendCompleted(Error(e)) -> #(
      model.Model(..m, sending: False, send_status: "Send failed: " <> e),
      effect.none(),
    )
  }
}

// --- view ------------------------------------------------------------------

fn option_for(selected: String, ref: model.ProfileRef) -> Element(Msg) {
  html.option(
    [attr.value(ref.path), attr.selected(ref.path == selected)],
    ref.vendor <> " / " <> ref.name,
  )
}

fn picker(
  label: String,
  refs: List(model.ProfileRef),
  selected: String,
  on_sel: fn(String) -> Msg,
) -> Element(Msg) {
  html.label([attr.class("field")], [
    html.span([], [text(label)]),
    html.select(
      [event.on_input(on_sel)],
      [
        html.option([attr.value("")], "— choose —"),
        ..list.map(refs, option_for(selected, _))
      ],
    ),
  ])
}

fn section(title: String, body: List(Element(Msg))) -> Element(Msg) {
  html.section([attr.class("card")], [
    html.h2([], [text(title)]),
    ..body
  ])
}

fn settings_form(settings: List(Setting)) -> Element(Msg) {
  html.div(
    [attr.class("grid")],
    list.map(settings, fn(s: Setting) {
      html.label([attr.class("field")], [
        html.span([], [text(s.label)]),
        html.input([
          attr.value(s.value),
          attr.placeholder("profile default"),
          event.on_input(fn(v) { SettingChanged(s.key, v) }),
        ]),
      ])
    }),
  )
}

fn viewer(m: Model) -> Element(Msg) {
  case m.model_url {
    None -> html.p([attr.class("muted")], [text("No model uploaded yet.")])
    Some(url) ->
      case m.model_ext {
        ".step" | ".stp" ->
          html.p([attr.class("muted")], [
            text(
              "STEP file uploaded — no in-browser preview, but it will slice.",
            ),
          ])
        _ ->
          element(
            "orca-model-viewer",
            [attribute("src", url), attr.class("viewer")],
            [],
          )
      }
  }
}

fn slice_section(m: Model) -> Element(Msg) {
  let btn_label = case m.slicing {
    True -> "Slicing…"
    False -> "Slice"
  }
  html.div([], [
    html.button(
      [event.on_click(ClickedSlice), attr.disabled(m.slicing)],
      [text(btn_label)],
    ),
    case m.gcode_url {
      Some(url) ->
        html.a(
          [attr.href(url), attribute("download", ""), attr.class("dl")],
          [text("Download G-code")],
        )
      None -> none()
    },
    case m.slice_log {
      "" -> none()
      log -> html.pre([attr.class("log")], [text(log)])
    },
  ])
}

fn printer_section(m: Model) -> Element(Msg) {
  html.div([attr.class("grid")], [
    html.label([attr.class("field")], [
      html.span([], [text("Moonraker URL (e.g. http://printer.local)")]),
      html.input([
        attr.value(m.printer_url),
        event.on_input(PrinterUrlChanged),
      ]),
    ]),
    html.label([attr.class("field")], [
      html.span([], [text("API key (optional)")]),
      html.input([
        attr.value(m.printer_key),
        event.on_input(PrinterKeyChanged),
      ]),
    ]),
    html.label([attr.class("check")], [
      html.input([
        attr.type_("checkbox"),
        attr.checked(m.start_print),
        event.on_check(ToggledStartPrint),
      ]),
      html.span([], [text("Start print after upload")]),
    ]),
    html.button(
      [event.on_click(ClickedSend), attr.disabled(m.sending)],
      [text("Send to printer")],
    ),
    case m.send_status {
      "" -> none()
      s -> html.p([attr.class("muted")], [text(s)])
    },
  ])
}

fn view(m: Model) -> Element(Msg) {
  let machines = case m.profiles {
    Some(p) -> p.machines
    None -> []
  }
  let processes = case m.profiles {
    Some(p) -> p.processes
    None -> []
  }
  let filaments = case m.profiles {
    Some(p) -> p.filaments
    None -> []
  }

  html.div([attr.class("app")], [
    html.style([], styles),
    html.header([], [
      html.h1([], [text("OrcaSlicer Web")]),
      html.p([attr.class("status")], [text(m.status)]),
    ]),
    section("1 · Model", [
      html.button([event.on_click(ClickedUpload)], [
        text("Upload STL / 3MF / STEP / OBJ"),
      ]),
      viewer(m),
    ]),
    section("2 · Printer & profiles", [
      html.div([attr.class("grid")], [
        picker("Printer", machines, m.sel_machine, SelectedMachine),
        picker("Process", processes, m.sel_process, SelectedProcess),
        picker("Filament", filaments, m.sel_filament, SelectedFilament),
      ]),
    ]),
    section("3 · Settings", [
      settings_form(m.settings),
      html.label([attr.class("field")], [
        html.span([], [
          text("Advanced overrides (one key=value per line)"),
        ]),
        html.textarea(
          [event.on_input(RawOverridesChanged)],
          m.raw_overrides,
        ),
      ]),
    ]),
    section("4 · Slice", [slice_section(m)]),
    section("5 · Send to Klipper / Moonraker", [printer_section(m)]),
  ])
}

const styles = "
*{box-sizing:border-box}
body{margin:0;font-family:system-ui,sans-serif;background:#0f1115;color:#e6e6e6}
.app{max-width:900px;margin:0 auto;padding:24px}
header h1{margin:0;font-size:22px}
.status{color:#7fd1b9;margin:4px 0 16px}
.card{background:#1a1d24;border:1px solid #2a2f3a;border-radius:10px;padding:16px;margin-bottom:16px}
.card h2{margin:0 0 12px;font-size:15px;color:#9ab}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px}
.field{display:flex;flex-direction:column;gap:4px;font-size:13px}
.field span{color:#9aa}
input,select,textarea{background:#0f1115;color:#e6e6e6;border:1px solid #2a2f3a;border-radius:6px;padding:8px;font:inherit}
textarea{min-height:80px;width:100%}
button{background:#2f6f5f;color:#fff;border:0;border-radius:6px;padding:10px 16px;cursor:pointer;font:inherit}
button:disabled{opacity:.5;cursor:default}
.dl{display:inline-block;margin-left:12px;color:#7fd1b9}
.viewer{display:block;width:100%;height:360px;background:#06080c;border-radius:8px;margin-top:12px}
.log{max-height:240px;overflow:auto;background:#06080c;padding:12px;border-radius:6px;font-size:12px;white-space:pre-wrap}
.muted{color:#889;font-size:13px}
.check{display:flex;align-items:center;gap:8px;font-size:13px}
"
