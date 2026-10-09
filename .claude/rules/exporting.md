---
description: Exporting builds — mise run build, the commit stamp behind #546's link gate, export-only traps (declared-but-missing GDExtension binary; PCK remap kills a runtime DirAccess scan; naming EditorInterface is a parse error)
paths:
  - "export_presets.cfg"
  - ".mise/tasks/build"
  - "autoload/build_info.gd"
  - "autoload/stat_registry.gd"
  - "stats_system/stat_def_roster.*"
  - "network/network_link.gd"
  - "native/*.gdextension"
---

Three traps only a real export shows: a **declared-but-missing GDExtension binary** is fatal at export (`build` refuses up front, #806); a runtime **`DirAccess` scan finds nothing in a PCK** (`.tres` becomes `.res` + `.tres.remap` — use an authored roster, #597 D13); and **naming `EditorInterface` in a shipping script** is a parse error that kills the whole script. Two exclusions that look dead are not: `addons/at-icons/control/` is faction art, `addons/stat_board_visualizer` is preloaded by shipped UI. An export is a directory (the GDExtension library ships beside the executable); `mise run build` stamps the commit. See docs/domain/exporting.md
