extends GutTest

## #281 Phase 2 — every addon scene carries a non-null tooltip icon.
##
## The icon is authored on each addon scene (`@export var icon` on
## SkillNodeAddon, pointing at an assets/icons/addons/ sprite rasterized by
## `mise run icons:update`). A missing row in addons/mapping.txt does NOT fail
## the task — it prints `✗ missing: … → skipping` and the run succeeds — so a
## bad source path silently ships a placeholder. This test is the lint that
## catches it: a null icon here means the scene's ExtResource didn't resolve.
##
## `icon == null` is still a *legal* state (the AddonItem falls back to its
## gradient placeholder) — this test asserts the five authored scenes opt in.

const _ADDON_SCENES := {
	"spike_ring": preload("res://skill_node/addons/spike_ring_addon.tscn"),
	"bunker": preload("res://skill_node/addons/bunker_addon.tscn"),
	"fortification": preload("res://skill_node/addons/fortification_addon.tscn"),
	"clamp": preload("res://skill_node/addons/clamp_addon.tscn"),
	"skill_dust": preload("res://skill_node/addons/skill_dust_addon.tscn"),
	"watchtower": preload("res://skill_node/addons/watchtower_addon.tscn"),
}


func test_every_addon_scene_carries_a_non_null_icon() -> void:
	for name in _ADDON_SCENES:
		var addon: SkillNodeAddon = _ADDON_SCENES[name].instantiate()
		add_child_autofree(addon)
		assert_not_null(addon.icon, "%s addon must carry a tooltip icon" % name)


func test_every_addon_icon_texture_has_image_data() -> void:
	for name in _ADDON_SCENES:
		var addon: SkillNodeAddon = _ADDON_SCENES[name].instantiate()
		add_child_autofree(addon)
		assert_not_null(addon.icon.get_image(), "%s icon texture must load from disk" % name)
