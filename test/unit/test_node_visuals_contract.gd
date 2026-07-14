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


## Declaring `_process` on the base class makes Godot enable processing on every
## subclass by default. Only components that asked for the clock may tick.
func test_only_animating_components_are_on_the_process_list() -> void:
	var comp = add_child_autofree(CompositeScene.instantiate())
	await get_tree().process_frame

	assert_false(comp.get_node("%InnerDisk").is_processing(), "a static disk never ticks")
	assert_false(comp.get_node("%RimRing").is_processing(), "a static rim never ticks")
	assert_true(comp.get_node("%RuneRing").is_processing(), "the rune ring spins (band_count > NONE)")


func test_animating_component_accumulates_shared_clock() -> void:
	var comp = add_child_autofree(CompositeScene.instantiate())
	await get_tree().process_frame
	var rune = comp.get_node("%RuneRing")
	var before: float = rune.anim_time
	await get_tree().process_frame
	assert_gt(rune.anim_time, before, "anim_time advances while animating")


## #172: the shader components must ship with NO baked `material` — the script
## binds the ONE shared static ShaderMaterial at runtime. A `material =
## SubResource(...)` serialized into the scene (an editor round-trip artifact)
## makes every instance, even a hidden one, claim a global instance-uniform
## buffer slot at load. This asserts the scene is clean; it goes red if an
## editor save re-bakes the material (which `_validate_property` prevents).
func test_disk_and_rim_ship_no_baked_material() -> void:
	var disk = autofree(DiskScene.instantiate())
	assert_null(disk.material, "InnerDisk.tscn must not bake a material (re-bake regression)")
	var rim = autofree(preload("res://skill_node/visuals/rim_ring.tscn").instantiate())
	assert_null(rim.material, "RimRing.tscn must not bake a material (re-bake regression)")


## The rim carries archetype identity and "activates" toward it on allocation:
## an unallocated node's rim reads mostly as its own bronze metal (tint_mix
## 0.3), an allocated one as full archetype tint (1.0) — a second allocation
## read alongside the disk lighting up. Guards the #172 approach-A removal,
## which dropped the loop that used to drive this.
func test_rim_tint_mix_tracks_allocation() -> void:
	var comp = add_child_autofree(CompositeScene.instantiate())
	await get_tree().process_frame
	var rim = comp.get_node("%RimRing")
	comp.allocation_level = 0
	assert_eq(rim.tint_mix, 0.3, "unallocated rim reads mostly bronze metal")
	comp.allocation_level = 1
	assert_eq(rim.tint_mix, 1.0, "allocated rim reads full archetype tint")


## #172: a fog-hidden node (the whole composite invisible) registers NO
## instance-uniform state on its shader children — no material bound, no
## uniform set — so it claims zero slots in the shared global buffer. This is
## the reason the gate reads is_visible_in_tree() rather than local `visible`.
func test_fog_hidden_composite_registers_no_instance_state() -> void:
	var comp = CompositeScene.instantiate()
	comp.visible = false
	add_child_autofree(comp)
	await get_tree().process_frame

	var disk = comp.get_node("%InnerDisk")
	var rim = comp.get_node("%RimRing")
	assert_null(disk.material, "hidden disk binds no material (claims no buffer slot)")
	assert_null(disk.get_instance_shader_parameter("tint_color"), "and sets no uniform")
	assert_null(rim.material, "hidden rim binds no material")
	assert_null(rim.get_instance_shader_parameter("inner_r"), "and sets no uniform")


## #172: un-fogging a node (composite becomes visible) syncs its shader
## children the frame they become visible — the `visibility_changed` re-sync —
## so a revealed disk/rim never renders with unset uniforms.
func test_unfogged_composite_syncs_on_becoming_visible() -> void:
	var comp = CompositeScene.instantiate()
	comp.visible = false
	add_child_autofree(comp)
	await get_tree().process_frame
	var disk = comp.get_node("%InnerDisk")
	assert_null(disk.get_instance_shader_parameter("tint_color"), "hidden: no uniform yet")

	comp.visible = true
	await get_tree().process_frame
	assert_not_null(disk.material, "revealed disk binds the shared material")
	assert_not_null(disk.get_instance_shader_parameter("tint_color"), "and gets its uniforms")
