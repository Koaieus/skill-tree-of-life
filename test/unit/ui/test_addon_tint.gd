extends GutTest

## An addon kind's accent colour is a fact of the addon scene, read through
## [method SkillNodeAddon.tint_of]: the armed badge, the melee blip and the
## temp-upgrade card all paint that one value, and [ActionPalette] no longer
## carries a per-addon category. The card accent rides on the blip colour
## ([method MeleeBody._upgrade_color] feeds `btn.accent`); its own assert lives
## in test_temp_upgrade_button.

var _catalog: TempUpgradeCatalog = preload("res://attack/melee/temp_upgrade_catalog.tres")
const _PALETTE := preload("res://ui/theme/action_palette.tres")
const _DEFS_DIR := "res://skill_node/addons/defs/"


func test_every_catalog_kind_paints_the_addon_scenes_tint() -> void:
	assert_gt(_catalog.offered().size(), 0, "fixture check: the catalog has kinds")
	for def: PackedScene in _catalog.offered():
		var expected := SkillNodeAddon.tint_of(def)
		assert_ne(expected, Color.TRANSPARENT, "%s has no authored tint" % def.resource_path)
		var mode := TempUpgradeMode.new(null, def)
		assert_eq(mode.icon_tint(), expected,
				"%s: the armed badge must paint the addon's own tint" % def.resource_path)
		assert_eq(MeleeBody._upgrade_color(def), expected,
				"%s: the melee blip must paint the addon's own tint" % def.resource_path)


func test_the_palette_has_no_addon_category() -> void:
	for key in [&"clamp", &"spike_ring", &"toxin"]:
		assert_eq(_PALETTE.color_for(key), Color.TRANSPARENT,
				"ActionPalette still maps addon id %s" % key)


func test_every_temp_placeable_addon_scene_authors_a_tint() -> void:
	var checked := 0
	for file in DirAccess.get_files_at(_DEFS_DIR):
		if not file.ends_with(".tscn"):
			continue
		var scene: PackedScene = load(_DEFS_DIR + file)
		if not SkillNodeAddon.temp_placeable_of(scene):
			continue
		checked += 1
		assert_ne(SkillNodeAddon.tint_of(scene), Color.TRANSPARENT,
				"%s is temp_placeable but authors no tint" % file)
	assert_gt(checked, 0, "fixture check: some addon scene is temp_placeable")
