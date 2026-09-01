---
description: Exporting builds — mise run build, the commit stamp behind #546's link gate, and the two export-only traps (PCK remap kills a runtime DirAccess scan; naming EditorInterface is a parse error)
paths:
  - "export_presets.cfg"
  - ".mise/tasks/build"
  - "autoload/build_info.gd"
  - "autoload/stat_registry.gd"
  - "stats_system/stat_def_roster.*"
  - "network/command_link.gd"
---

`mise run build` exports linux+windows one-file builds and stamps the commit into `build_stamp.cfg`, so #546's sha gate still refuses a mismatched link between two *builds*. Two failures only a real export can show: a runtime `DirAccess` scan finds nothing in a PCK (`.tres` becomes `.res` + `.tres.remap` — use an authored roster, #597 D13), and naming `EditorInterface` in a shipping script is a parse error that kills the whole script. Two exclusions that look dead are not: `addons/at-icons/control/` is faction art, `addons/stat_board_visualizer` is preloaded by shipped UI. See docs/domain/exporting.md
