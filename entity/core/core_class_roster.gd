@tool
class_name CoreClassRoster
extends Resource

## The authored, ordered set of [CoreClass]es a RUNTIME caller may offer a
## picker (#640). [method CoreClass.load_all] discovers classes with a
## `DirAccess` scan of [constant CoreClass.DIR] — fine for editor and test
## code, but the exporter's default `.tres`->`.res` remap
## (`convert_text_resources_to_binary`, unset here and true by default)
## rewrites every `.tres` into a `.res` + `.tres.remap` pair inside the PCK.
## `DirAccess.get_files_at()` lists what the PCK actually contains, so a
## `file.ends_with(".tres")` filter matches nothing there — `load_all()`
## quietly returns `[]` in an exported build even though `load()` itself still
## resolves the remap transparently. Confirmed 2026-08-27 (#640) via a real
## `--export-pack` run.
##
## The house rule this applies (#597 D13): **directory scan for editor and
## test code, authored array for runtime.** Each entry here is an `ExtResource`
## — a hard dependency edge the exporter can't strip or rename out from under —
## so [method CoreClass.pickable_for] reads this instead of [method CoreClass.load_all].
##
## Authored order is also the picker's order, deliberately — a scan only ever
## gives alphabetical.
##
## Not a substitute for [method CoreClass.load_all]: the #322 DAG check needs
## a newly authored, unreferenced `CoreClass.tres` to still surface, which an
## authored array could never guarantee. A class must be added here separately
## to become pickable — the same curation cost [PlayerPalette] already pays.
@export var classes: Array[CoreClass] = []
