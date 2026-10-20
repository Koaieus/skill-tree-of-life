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


## Scanned once, on first read; [member folder] is authoring-time data.
var _kinds: Array[PackedScene] = []
var _scanned := false


## Every [SkillNodeAddon]-rooted scene in [member folder], sorted by file name.
## Lists through [method ResourceLoader.list_directory], which resolves the
## `.remap` an exported build leaves behind.
func kinds() -> Array[PackedScene]:
	if not _scanned:
		_scanned = true
		var files: Array[String] = []
		for f in ResourceLoader.list_directory(folder):
			if f.get_extension() == "tscn":
				files.append(f)
		files.sort()
		for f in files:
			var scene := load(folder.path_join(f)) as PackedScene
			if SkillNodeAddon.is_addon_scene(scene):
				_kinds.append(scene)
	return _kinds


## The [member SkillNodeAddon.temp_placeable] subset of [method kinds] in the
## shop's canonical order — the one owner of it, read by the blade-node fan and
## the quickbar auto-fill: grouped by [member SkillNodeAddon.role] in enum
## order, blade-size price ascending within a role, scene path breaking ties.
func offered() -> Array[PackedScene]:
	var out: Array[PackedScene] = []
	for scene in kinds():
		if SkillNodeAddon.temp_placeable_of(scene):
			out.append(scene)
	out.sort_custom(_precedes)
	return out


static func _precedes(a: PackedScene, b: PackedScene) -> bool:
	var role_a := SkillNodeAddon.role_of(a)
	var role_b := SkillNodeAddon.role_of(b)
	if role_a != role_b:
		return role_a < role_b
	var price_a := _blade_price(a)
	var price_b := _blade_price(b)
	if price_a != price_b:
		return price_a < price_b
	return a.resource_path < b.resource_path


static func _blade_price(scene: PackedScene) -> int:
	return SkillNodeAddon.temp_costs_of(scene, 0).get(&"blade_size", 0)


## The kind whose scene path is [param kind] — the very [PackedScene]
## [method kinds] holds — or null if there is none.
func by_kind(kind: String) -> PackedScene:
	if kind.is_empty():
		return null
	for scene in kinds():
		if scene.resource_path == kind:
			return scene
	return null
