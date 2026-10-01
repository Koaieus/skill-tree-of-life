class_name TempUpgradeCatalog
extends Resource

## The temp-upgrade kinds: every [SkillNodeAddon]-rooted scene in [member folder],
## offered where [member SkillNodeAddon.temp_placeable]. Authored as
## `attack/melee/temp_upgrade_catalog.tres` and reaching consumers through
## [member BattleSystem.temp_upgrade_catalog] — an `@export` wired by the
## composing scene, never a static door: a Resource script that `preload`s a
## `.tres` whose script is itself is a parse-time cycle, and a static default
## is not inspector-composable.
##
## A kind is its scene ([method SkillNodeAddon.get_kind] is the scene path);
## nobody hand-maintains the list. A base/template addon scene lives beside the
## source in `skill_node/addons/`, never in the scanned folder.

## The scanned folder. Tray / button / hotkey order is file-name order.
@export_dir var folder: String = "res://skill_node/addons/defs"


## Every addon scene in [member folder], sorted by file name.
func kinds() -> Array[PackedScene]:
	return []


## The [member SkillNodeAddon.temp_placeable] subset of [method kinds], in order.
func offered() -> Array[PackedScene]:
	return []


## The kind whose scene path is [param kind] — the very [PackedScene]
## [method kinds] holds — or null if there is none.
func by_kind(_kind: String) -> PackedScene:
	return null
