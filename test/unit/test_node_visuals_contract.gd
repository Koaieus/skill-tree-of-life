extends GutTest
## The SkillNode-visuals identity + lighting contract (#16 foundation).
##
## Identity (entity_tint / archetype_tint / allocated) is loop-set by the
## composite onto EVERY child, so a component can't be added and then silently
## left out of a hand-written fan-out. Lighting travels separately, as ONE
## shared [LightingStyle] object whose `changed` re-pushes — so the disk and
## its rim can never drift onto two different lights.

## NodeVisualsComposite declares no `class_name` (leaf visual components in this
## family deliberately do not — see .claude/rules/skill-node-visuals.md), so its
## constants are reachable only through the script resource.
const CompositeScript := preload("res://skill_node/visuals/node_visuals_composite.gd")
const CompositeScene := preload("res://skill_node/visuals/node_visuals_composite.tscn")
const DiskScene := preload("res://skill_node/visuals/inner_disk.tscn")
## Shelved out of the composite (#238) but still the family's clearest animating
## component, so the shared-clock tests below drive it standalone. The half of
## those tests that guards the base-class `_process` auto-enable trap is the
## `assert_false` on the composite's own static children; this is the positive
## control that keeps "and a component that ASKED for the clock gets it" honest.
const RuneRingScene := preload("res://skill_node/visuals/rune_ring.tscn")


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
		"the carve glyph rides the disk's OWN shader uniforms now (folded into inner_disk.gdshader) — " +
		"it can't drift from the disk's tint because there's only one material to drift from"
	)


## Declaring `_process` on the base class makes Godot enable processing on every
## subclass by default. Only components that asked for the clock may tick.
func test_only_animating_components_are_on_the_process_list() -> void:
	var comp = add_child_autofree(CompositeScene.instantiate())
	await get_tree().process_frame

	assert_false(comp.get_node("%InnerDisk").is_processing(), "a static disk never ticks")
	assert_false(comp.get_node("%RimRing").is_processing(), "a static rim never ticks")

	var rune = add_child_autofree(RuneRingScene.instantiate())
	await get_tree().process_frame
	assert_true(rune.is_processing(), "the rune ring spins (band_count > NONE)")


func test_animating_component_accumulates_shared_clock() -> void:
	var rune = add_child_autofree(RuneRingScene.instantiate())
	await get_tree().process_frame
	var before: float = rune.anim_time
	await get_tree().process_frame
	assert_gt(rune.anim_time, before, "anim_time advances while animating")


## #172: the shader components must ship with NO baked `material` — the script
## binds the ONE shared static ShaderMaterial at runtime. A `material =
## SubResource(...)` serialized into the scene (an editor round-trip artifact)
## makes every instance, even a hidden one, claim a global instance-uniform
## buffer slot at load. This asserts the scene is clean; it goes red if an
## editor save re-bakes the material (which `_validate_property` prevents).
## A baked `material` is only half the regression. Scene instantiation also
## applies a serialized `instance_shader_parameters/*` block by name via
## `set()`, and that path does NOT go through `_validate_property` — so those
## lines claim buffer slots from load just as surely, while leaving `material`
## null and this test green. Both scenes must ship clean of both.
func test_disk_and_rim_ship_no_baked_material_or_instance_params() -> void:
	var disk = autofree(DiskScene.instantiate())
	assert_null(disk.material, "InnerDisk.tscn must not bake a material (re-bake regression)")
	assert_null(
		disk.get_instance_shader_parameter("tint_color"),
		"InnerDisk.tscn must not bake instance_shader_parameters/* either"
	)
	var rim = autofree(preload("res://skill_node/visuals/rim_ring.tscn").instantiate())
	assert_null(rim.material, "RimRing.tscn must not bake a material (re-bake regression)")
	assert_null(
		rim.get_instance_shader_parameter("inner_r"),
		"RimRing.tscn must not bake instance_shader_parameters/* either"
	)


## The composite is the third scene that round-trips through the editor with
## these children instanced, so it is a third place the block can re-bake —
## and the one that matters most, since it is what the board instantiates
## 500–2500 times.
func test_composite_ships_no_instance_params_on_its_shader_children() -> void:
	var comp = autofree(CompositeScene.instantiate())
	var disk = comp.get_node("%InnerDisk")
	var rim = comp.get_node("%RimRing")
	assert_null(
		disk.get_instance_shader_parameter("tint_color"),
		"the composite must not re-bake the disk's instance params"
	)
	assert_null(
		rim.get_instance_shader_parameter("ring_tint"),
		"the composite must not re-bake the rim's instance params"
	)


## The rim carries archetype identity and "activates" toward it on allocation.
## Guards the #172 approach-A removal, which dropped the loop that used to
## drive this.
##
## Asserts against the CONSTANTS, not literals. This test used to hardcode
## 0.3 → 1.0 and went red when the swing was retuned to 0.8 → 0.9 for
## legibility (owner-confirmed 2026-08-14: the strongly tinted rim is what
## makes a node readable at board zoom, and bronze-dominant did not read).
## Hardcoding the numbers pinned a look nobody had agreed to keep; what the
## contract actually owes is that allocation MOVES the tint and that both ends
## stay colourful.
func test_rim_tint_mix_tracks_allocation() -> void:
	var comp = add_child_autofree(CompositeScene.instantiate())
	await get_tree().process_frame
	var rim = comp.get_node("%RimRing")
	comp.allocation_level = 0
	assert_almost_eq(rim.tint_mix, CompositeScript.UNFILLED_TINT_MIX, 0.0001,
		"unallocated rim sits at the unfilled tint ratio")
	comp.allocation_level = 1
	assert_almost_eq(rim.tint_mix, CompositeScript.FILLED_TINT_MIX, 0.0001,
		"allocated rim sits at the filled tint ratio")
	assert_gt(CompositeScript.FILLED_TINT_MIX, CompositeScript.UNFILLED_TINT_MIX,
		"allocation must move the rim TOWARD the archetype tint, not away")
	assert_gt(CompositeScript.UNFILLED_TINT_MIX, 0.5,
		"even unallocated, the rim stays archetype-tinted — it is the legibility read")


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


## #141: a sensed node draws its own archetype-only outline while the shader
## children stay hidden — so a sensed node claims ZERO instance-uniform slots
## (the same #172 gate as fog-hidden) AND the sensed representation is a real,
## structural part of the composite, not a legacy renderer standing in. Hiding
## the shader stack (a grouping node) rather than each child keeps CorePresence
## on its own visibility flag.
func test_sensed_composite_hides_shader_children_and_shows_outline() -> void:
	var comp = CompositeScene.instantiate()
	comp.sensed = true
	add_child_autofree(comp)
	await get_tree().process_frame

	var disk = comp.get_node("%InnerDisk")
	var rim = comp.get_node("%RimRing")
	assert_false(disk.is_visible_in_tree(), "sensed: InnerDisk hidden — claims no buffer slot")
	assert_false(rim.is_visible_in_tree(), "sensed: RimRing hidden")
	assert_null(disk.material, "sensed disk binds no material (zero buffer slot, like fog-hidden)")
	assert_true(comp.get_node("%SensedOutline").visible, "sensed: the archetype outline is shown")


## #141: un-sensing restores the shader stack and re-binds materials — sensed is
## a reversible display state, not a one-way teardown.
func test_unsensing_restores_shader_stack_and_hides_outline() -> void:
	var comp = CompositeScene.instantiate()
	comp.sensed = true
	add_child_autofree(comp)
	await get_tree().process_frame

	comp.sensed = false
	await get_tree().process_frame

	var disk = comp.get_node("%InnerDisk")
	assert_true(disk.is_visible_in_tree(), "un-sensed: InnerDisk visible again")
	assert_not_null(disk.material, "and re-binds the shared material")
	assert_false(comp.get_node("%SensedOutline").visible, "outline hidden when not sensed")


## #478 perf amendment: a hidden Node2D still runs `_process` every frame in
## Godot — `visible = false` alone only skips `_draw`. CoreHalos' GIMBAL preset
## is a 28-segment quaternion-chained hoop stack redrawn every tick (see
## .claude/rules/skill-node-visuals.md), so a non-core node (the overwhelming
## majority of 500-2500/level) must not merely hide CorePresence, it must stop
## it PROCESSING — `_apply_core_active` now also drives `process_mode`.
func test_inactive_core_presence_is_hidden_and_off_the_process_list() -> void:
	var comp = add_child_autofree(CompositeScene.instantiate())
	await get_tree().process_frame
	var presence = comp.get_node("%CorePresence")

	comp.core_active = true
	await get_tree().process_frame
	assert_true(presence.visible, "active core: CorePresence shown")
	assert_eq(
		presence.process_mode, Node.PROCESS_MODE_INHERIT,
		"active core: CorePresence processes normally")
	var halos = presence.get_node("CoreHalos")
	assert_true(halos.is_processing(), "active core: CoreHalos (GIMBAL by default) is ticking")

	comp.core_active = false
	await get_tree().process_frame
	assert_false(presence.visible, "inactive core: CorePresence hidden")
	assert_eq(
		presence.process_mode, Node.PROCESS_MODE_DISABLED,
		"inactive core: CorePresence's whole subtree stops processing")


## #478: overriding [member SkillNode.core_halo_style] on a live node routes
## through the composite → CorePresence → CoreHalos chain (never a hardcoded
## grandchild path reaching past CorePresence — that scene is nested and
## reusable, see core_presence.gd). `-1` (Default) is a deliberate no-op, so a
## normal core's authored GIMBAL is untouched by a node that never sets this.
func test_core_halo_style_override_routes_through_the_chain() -> void:
	var comp = add_child_autofree(CompositeScene.instantiate())
	await get_tree().process_frame
	var halos = comp.get_node("%CorePresence").get_node("CoreHalos")
	var CoreHalosScript := preload("res://skill_node/visuals/core_halos.gd")

	assert_eq(
		halos.halo_style, CoreHalosScript.CoreHaloStyle.GIMBAL,
		"authored default (a normal core) is GIMBAL")

	comp.set_core_halo_style(-1)
	assert_eq(
		halos.halo_style, CoreHalosScript.CoreHaloStyle.GIMBAL,
		"-1 (Default) is a no-op — leaves the authored style alone")

	comp.set_core_halo_style(CoreHalosScript.CoreHaloStyle.COG)
	assert_eq(
		halos.halo_style, CoreHalosScript.CoreHaloStyle.COG,
		"a blocked node's cheap-halo override lands on the live CoreHalos child")
