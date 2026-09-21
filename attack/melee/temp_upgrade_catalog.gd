class_name TempUpgradeCatalog
extends Resource

## The offerable temp-upgrade kinds (#406), authored as
## `attack/melee/temp_upgrade_catalog.tres` and reaching consumers through
## [member BattleSystem.temp_upgrade_catalog] — an `@export` wired by the
## composing scene, never a static door: a Resource script that `preload`s a
## `.tres` whose script is itself is a parse-time cycle, and a static default
## is not inspector-composable.

## Tray / button / hotkey order.
@export var kinds: Array[TempUpgradeDef] = []


## The loaded def named by [param id] — the very object [member kinds] holds,
## so identity checks keep working — or null if there is none.
func by_id(id: StringName) -> TempUpgradeDef:
	if id == &"":
		return null
	for def in kinds:
		if def != null and def.id == id:
			return def
	return null
