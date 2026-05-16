# OrcaSlicer Web UI

A browser UI for OrcaSlicer: upload a model, pick a printer/profile, tweak
settings, slice, download the G-code, and push it to a Klipper/Moonraker
printer.

Full **Gleam** stack, Docker, monorepo:

| Folder      | Tech                                   | Role |
|-------------|----------------------------------------|------|
| `backend/`  | Gleam + Wisp/Mist on the BEAM          | REST API that wraps the headless `orca-slicer` CLI and the Moonraker HTTP API |
| `frontend/` | Gleam + Lustre (compiled to JS)        | Single-page UI; Three.js custom element for the 3D preview |

### Why not WASM / Cloudflare Workers?

`src/libslic3r` depends on CGAL, OpenCASCADE, GMP/MPFR, TBB and Boost. None
have production WASM ports, and Workers cannot run a native binary. Slicing
therefore runs as a native CLI subprocess inside the backend container. The
frontend is plain static JS, so it *can* be hosted anywhere (incl. Workers/
Pages) as long as it can reach the backend.

## Run it

```bash
cd webui
docker compose up --build
# open http://localhost:8088
```

> The backend image **compiles OrcaSlicer from this repo** the first time
> (`build_linux.sh -u -dr -sr -ir`). That is long (deps + slic3r). Subsequent
> builds are cached.

### Faster path — use a prebuilt AppImage instead of compiling

If you already have an OrcaSlicer AppImage (or a release URL), you can skip the
long source build. Replace the `orca` stage in `backend/Dockerfile` with a slim
Ubuntu base that:

1. installs `xvfb` and the GTK/WebKit runtime libs
   (see the `apt-get` list in `scripts/Dockerfile`),
2. `./Orca*.AppImage --appimage-extract` into `/opt/orca`,
3. sets `ORCA_BIN=/opt/orca/squashfs-root/AppRun` and `ORCA_PROFILES_DIR`
   to the extracted `resources/profiles`.

The Erlang/Gleam install + `gleam build`/`gleam run` runtime stage and
everything else (compose, frontend, env vars) are unchanged.

## How a slice works

```
browser ──▶ Caddy (frontend) ──▶ /api/* , /files/* ──▶ backend (Wisp)
                                                          │
   POST /api/upload     store model under /tmp/orca/<job>/model.<ext>
   GET  /api/profiles   scan resources/profiles/<Vendor>/{machine,process,filament}
   POST /api/slice      orca-slicer --load-settings "M;P[;override]"
                                    --load-filaments F --slice 0
                                    --outputdir <job>/out <model>
   GET  /files/<job>/out/<file>.gcode      (static download)
   POST /api/send-to-printer   Moonraker /server/files/upload (+ /printer/print/start)
```

User setting tweaks are written to a tiny `override.json` *process* profile
that the CLI loads **after** the base profile, so its values win — no JSON
merging on our side. Profile JSON files are read in place and never modified
(backward-compat / no-regression: `webui/` is fully additive — no C++, CMake
or profile changes).

## Verify

Backend unit tests (pure functions — no CLI/network needed):

```bash
cd webui/backend && gleam test
```

Covers profile path-traversal guarding, CLI argument construction (override
ordering), and the Moonraker multipart body shape.

Frontend compiles:

```bash
cd webui/frontend && gleam run -m lustre/dev build app
```

End-to-end:

1. `docker compose up --build`, open <http://localhost:8088>
2. Upload `tests/data/test_3mf/Prusa.stl` (preview should render)
3. Pick a printer + process + filament profile
4. Optionally set e.g. *Layer height = 0.16*
5. **Slice** → CLI log appears, **Download G-code** becomes available; the
   `.gcode` is non-empty
6. **Send to Klipper**: enter a Moonraker base URL (+ API key if required),
   optionally tick *Start print*. Without a real printer, verify the request
   shape via the `multipart_body` unit test.

## Scope (v1)

- STEP/STP slices but is **not previewed** in-browser (no STEP loader).
- Settings editor = curated common keys + a raw `key=value` overrides box,
  not the full 1000+ key `PrintConfig` schema.
- Slice is request/response (CLI log returned); no live progress stream.
- The Gleam image tags in the Dockerfiles
  (`ghcr.io/gleam-lang/gleam:v1.11.0-*`) may need bumping to a currently
  published tag.
