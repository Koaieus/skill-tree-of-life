extends GutTest

## A draw-only addon is a base-script SkillNodeAddon scene with an AddonVisual
## child; the addon forwards the carrier radius to every AddonVisual child.

const SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const BASE_SCRIPT := preload("res://skill_node/addons/skill_node_addon.gd")
const SPIKE_RING_SCRIPT := preload("res://skill_node/addons/spike_ring_addon.gd")

const _DRAW_ONLY := [
	"res://skill_node/addons/defs/bunker_addon.tscn",
	"res://skill_node/addons/defs/fortification_addon.tscn",
	"res://skill_node/addons/defs/watchtower_addon.tscn",
]
const _SPIKE_RING := "res://skill_node/addons/defs/spike_ring_addon.tscn"


func _instance(path: String) -> SkillNodeAddon:
	var addon := (load(path) as PackedScene).instantiate() as SkillNodeAddon
	autofree(addon)
	return addon


func _visuals(addon: Node) -> Array[AddonVisual]:
	var out: Array[AddonVisual] = []
	for child in addon.get_children():
		if child is AddonVisual:
			out.append(child)
	return out


func test_draw_only_addons_run_the_base_script() -> void:
	for path in _DRAW_ONLY:
		var addon := _instance(path)
		assert_eq(addon.get_script(), BASE_SCRIPT, "%s root runs SkillNodeAddon itself" % path)
		assert_eq(_visuals(addon).size(), 1, "%s has an AddonVisual child" % path)


func test_spike_ring_keeps_its_subclass_and_draws_in_a_child() -> void:
	var addon := _instance(_SPIKE_RING)
	assert_eq(addon.get_script(), SPIKE_RING_SCRIPT, "spike ring keeps its behaviour subclass")
	assert_eq(_visuals(addon).size(), 1, "spike ring draws in an AddonVisual child")


func test_configure_visual_forwards_radius_to_every_visual_child() -> void:
	for path in _DRAW_ONLY + [_SPIKE_RING]:
		var addon := _instance(path)
		addon.configure_visual(41.5)
		var visuals := _visuals(addon)
		assert_false(visuals.is_empty(), "%s has a visual to forward to" % path)
		for v in visuals:
			assert_almost_eq(v.radius, 41.5, 0.001, "%s visual took the radius" % path)


func test_entering_a_carrier_seeds_the_visual_radius() -> void:
	for path in _DRAW_ONLY + [_SPIKE_RING]:
		var node: SkillNode = SKILL_NODE_SCENE.instantiate()
		node.base_radius = 47.0
		add_child_autofree(node)
		await get_tree().process_frame
		var addon := (load(path) as PackedScene).instantiate() as SkillNodeAddon
		node.add_child(addon)
		var visuals := _visuals(addon)
		assert_false(visuals.is_empty(), "%s has a visual to seed" % path)
		for v in visuals:
			assert_almost_eq(v.radius, node.radius, 0.001, "%s visual seeded from carrier" % path)
