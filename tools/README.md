# tools/

Dev-time scripts, not shipped gameplay. One line each; the mise task is how you run it.

| Path | What it is | Run with |
|---|---|---|
| `bake_svg_sdf.py` | SVG to msdfgen SDF to the carve-LUT PNGs (`docs/domain/emblem-bake.md`) | `mise run icons:update` |
| `disc_reach.py` | Design probe: nodes a Fire blast disc reaches on simulated procgen maps, with a Lightning-ladder fit (`docs/design/elements/casting.md`) | `python3 tools/disc_reach.py --a 3 --b 0 --powers 1,2,3,4` (no task) |
| `bake_carve_atlas.gd` | Packs the baked per-icon LUTs into the `CarveAtlas` the shader samples | `mise run icons:update` (last stage) |
| `gen_sandbox_tabs.gd` | One-off generator for `sandbox_host.tscn` (`docs/domain/sandbox-framework.md`) | `godot --headless --script res://tools/gen_sandbox_tabs.gd` (no task) |
| `balance/` | Balance harness: scenario table, ratio invariants, 1-D sensitivity slice (`balance/README.md`) | `mise run balance`, `mise run balance:sensitivity` |
| `curl_spectrum/` | Cyclone coefficient sweep: spectral radius and 8-wave damage over procgen terrain (`curl_spectrum/README.md`) | `mise run curl-spectrum` |
| `blade_playground/` | Interactive blade/swing playground scene | `mise run playground` |
| `shatter_capture.gd`, `shatter_capture.tscn` | Throwaway frame-by-frame PNG capture of the node-kill shatter VFX | none (see below) |

`shatter_capture.*` is referenced by nothing else in the repo (no mise task, no doc, no test); it is a candidate for a task or deletion.
