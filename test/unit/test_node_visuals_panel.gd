extends GutTest

## The node-visuals sandbox panel. It's dev tooling, so the only things worth
## pinning are the ones that break silently: that the lab slot really is a
## SkillNode inherited from the shipped scene (not a hand-composed lookalike
## that can drift), and that the tab's loader actually reaches both previews.

const PanelScene := preload("res://skill_node/visuals/panel/node_visuals_panel.tscn")
@warning_ignore("shadowed_global_identifier")
const PolygonCarveShape = preload("res://skill_node/visuals/emblem/polygon_carve_shape.gd")


func _panel() -> Control:
	var p: Control = PanelScene.instantiate()
	add_child_autofree(p)
	return p


func test_lab_slot_is_a_real_skill_node() -> void:
	var panel := _panel()
	await get_tree().process_frame
	var lab = panel.get_node("ViewportContainer/World/LabSlot/SkillNodeLab")
	assert_true(lab is SkillNode, "the lab slot is the real SkillNode, inherited — not a lookalike")
	# Inherited-scene overrides must survive instancing (see godot-workflow.md's
	# script-before-export-override gotcha, which silently drops them).
	assert_eq(lab.stake_level, 3, "the lab's authored stake override survives")
	assert_eq(lab.radius, 44.0, "and drives the derived radius")


func test_loader_drives_both_the_composite_and_the_lab() -> void:
	var panel := _panel()
	await get_tree().process_frame
	var shape := PolygonCarveShape.new()
	shape.sides = 8
	panel.load_carve_shape(shape)
	var composite = panel.get_node("ViewportContainer/World/CompositeSlot/Composite")
	var lab = panel.get_node("ViewportContainer/World/LabSlot/SkillNodeLab")
	assert_eq(composite.carve_shape, shape, "composite slot takes the shape pre-resolved")
	assert_eq(lab.archetype.carve_shape, shape, "the lab resolves it through the real emblem pipeline")


func test_loader_ignores_non_carve_shapes() -> void:
	var panel := _panel()
	await get_tree().process_frame
	var shape := PolygonCarveShape.new()
	shape.sides = 8
	panel.load_carve_shape(shape)
	panel.load_carve_shape(Image.create(2, 2, false, Image.FORMAT_RGBA8))
	var lab = panel.get_node("ViewportContainer/World/LabSlot/SkillNodeLab")
	assert_eq(lab.archetype.carve_shape, shape, "clicking a non-shape in the dock doesn't wipe the preview")
