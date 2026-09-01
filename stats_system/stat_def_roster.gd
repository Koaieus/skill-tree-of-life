@tool
class_name StatDefRoster
extends Resource

## Every authored [StatDef], as an array of hard `ExtResource` edges.
##
## [b]This exists because a directory scan does not survive export.[/b] The
## exporter's default `convert_text_resources_to_binary` rewrites every `.tres`
## into a `.res` + `.tres.remap` pair inside the PCK, so a
## `DirAccess`-plus-`ends_with(".tres")` walk of `stats_system/defs/` matches
## nothing there and yields an empty registry — in an exported build, every
## single stat lookup then failed with "unknown stat id". #640 found and fixed
## exactly this shape for [CoreClassRoster]; [StatRegistry] was the same bug,
## still live, and only a real export can show it.
##
## The house rule (#597 D13): **directory scan for editor and test code,
## authored array for runtime.** [StatRegistry] is an autoload every runtime
## stat lookup goes through, so it reads this and never scans.
##
## Unlike [CoreClassRoster] this is not a curated SUBSET — it must list every
## def in [constant StatRegistry.STAT_LIST_DIR], because the registry is the
## only door onto them. `test/unit/test_stat_def_roster.gd` fails the moment
## the directory and this array disagree, so adding a def without adding it
## here is a red suite, not a silent hole in a build nobody runs.

@export var defs: Array[StatDef] = []
