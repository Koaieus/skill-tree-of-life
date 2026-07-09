extends GutTest
## The SkillNode-visuals identity + lighting contract (#16 foundation).
##
## Identity (entity_tint / archetype_tint / allocated) is loop-set by the
## composite onto EVERY child, so a component can't be added and then silently
## left out of a hand-written fan-out. Lighting travels separately, as ONE
## shared [LightingStyle] object whose `changed` re-pushes — so the disk and
## its rim can never drift onto two different lights.

const CompositeScene := preload("res://skill_node/visuals/node_visuals_composite.tscn")
const DiskScene := preload("res://skill_node/visuals/inner_disk.tscn")


func test_lighting_style_emits_changed_on_set() -> void:
	var style := LightingStyle.new()
	watch_signals(style)
	style.highlight_intensity = 0.5
	assert_signal_emitted(style, "changed", "assigning a field emits changed")


func test_consumer_applies_lighting_on_assign_and_on_change() -> void:
	var disk = add_child_autofree(DiskScene.instantiate())
	await get_tree().process_frame

	var style := LightingStyle.new()
	style.highlight_position = Vector2(0.2, 0.4)
	disk.lighting = style
	assert_eq(disk.highlight_position, Vector2(0.2, 0.4), "assign pushes values in")

	style.highlight_position = Vector2(-0.9, 0.1)
	assert_eq(disk.highlight_position, Vector2(-0.9, 0.1), "changed signal re-pushes")


func test_composite_shares_one_lighting_across_lit_children() -> void:
	var comp = add_child_autofree(CompositeScene.instantiate())
	await get_tree().process_frame

	var disk = comp.get_node("%InnerDisk")
	var rim = comp.get_node("%RimRing")
	assert_not_null(disk.lighting, "InnerDisk received a light")
	assert_same(disk.lighting, rim.lighting, "RimRing shares the SAME light object")


## The point of the hoist: identity reaches EVERY child, not a hand-picked few.
func test_composite_pushes_identity_to_every_child() -> void:
	var comp = add_child_autofree(CompositeScene.instantiate())
	await get_tree().process_frame

	comp.entity_tint = Color(0.1, 0.7, 0.3)
	comp.archetype_tint = Color(0.8, 0.2, 0.2)
	comp.allocation_level = 1

	for child in comp.find_children("*", "", true, false):
		if not (child is SkillNodeVisual):
			continue
		assert_eq(child.entity_tint, Color(0.1, 0.7, 0.3), "%s got entity_tint" % child.name)
		assert_eq(child.archetype_tint, Color(0.8, 0.2, 0.2), "%s got archetype_tint" % child.name)
		assert_true(child.allocated, "%s got allocated" % child.name)


func test_disk_renders_the_entity_identity_through_its_shader() -> void:
	var comp = add_child_autofree(CompositeScene.instantiate())
	await get_tree().process_frame

	comp.entity_tint = Color(0.1, 0.7, 0.3)
	var disk = comp.get_node("%InnerDisk")
	assert_eq(
		disk.get_instance_shader_parameter("tint_color"), Color(0.1, 0.7, 0.3),
		"the weld glyph rides the disk's OWN shader uniforms now (folded into inner_disk.gdshader) — " +
		"it can't drift from the disk's tint because there's only one material to drift from"
	)
