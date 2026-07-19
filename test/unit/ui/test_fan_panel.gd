extends GutTest

## Tooltip V2 (#159): FanPanel wraps whichever skin Control is hand-placed as
## its first child (GlassPanel/HoloPanel — swap by editing the child, per
## #215's "which packed scene" decision, not a runtime enum) and forwards a
## single `glow` knob per skin type. Reveal is the shared clock-driven
## progress(0..1) contract, not a Tween recipe. See docs/domain/tooltip-fan.md.

const _SCENE := preload("res://ui/tooltip_fan/fan_panel.tscn")
const _HOLO_SCENE := preload("res://ui/theme/holo_panel.tscn")


func _make() -> FanPanel:
	var panel := _SCENE.instantiate() as FanPanel
	add_child(panel)
	autofree(panel)
	return panel


func test_default_skin_is_the_hand_placed_glass_panel() -> void:
	var panel := _make()
	await get_tree().process_frame
	assert_true(panel.get_skin() is GlassPanel, "fan_panel.tscn ships a GlassPanel skin by default")


func test_swapping_the_skin_child_to_holo_is_picked_up() -> void:
	var panel := _make()
	await get_tree().process_frame
	var glass := panel.get_skin()
	panel.remove_child(glass)
	autofree(glass)
	var holo := _HOLO_SCENE.instantiate()
	panel.add_child(holo)
	assert_true(panel.get_skin() is HoloPanel, "swapping the child scene swaps the resolved skin")


func test_glow_forwards_to_holo_panel_directly() -> void:
	var panel := _make()
	await get_tree().process_frame
	var glass := panel.get_skin()
	panel.remove_child(glass)
	autofree(glass)
	var holo := _HOLO_SCENE.instantiate() as HoloPanel
	panel.add_child(holo)
	panel.glow = 0.7
	assert_almost_eq(holo.glow, 0.7, 0.001, "HoloPanel.glow reads FanPanel.glow directly")


func test_glow_maps_onto_glass_panel_strength_and_tint_alpha() -> void:
	var panel := _make()
	await get_tree().process_frame
	panel.glow_tint = Color(0.5, 0.6, 0.7)
	panel.glow = 0.5
	var glass := panel.get_skin() as GlassPanel
	assert_almost_eq(glass.glow_strength, 20.0, 0.001, "glow_strength = glow * 40")
	assert_almost_eq(glass.glow_color.a, 0.5, 0.001, "glow_color alpha carries glow")
	assert_almost_eq(glass.glow_color.r, 0.5, 0.001, "glow_color rgb carries glow_tint")


func test_set_progress_zero_parks_at_start_scale_and_hidden() -> void:
	var panel := _make()
	await get_tree().process_frame
	panel.start_scale = 0.8
	panel.set_progress(0.0)
	assert_almost_eq(panel.scale.x, 0.8, 0.001)
	assert_almost_eq(panel.modulate.a, 0.0, 0.001)


func test_set_progress_one_settles_at_full_scale_and_visible() -> void:
	var panel := _make()
	await get_tree().process_frame
	panel.set_progress(1.0)
	assert_almost_eq(panel.scale.x, 1.0, 0.001)
	assert_almost_eq(panel.modulate.a, 1.0, 0.001)


func test_set_progress_clamps_out_of_range_input() -> void:
	var panel := _make()
	await get_tree().process_frame
	panel.set_progress(2.0)
	assert_almost_eq(panel.modulate.a, 1.0, 0.001, "t > 1 clamps to the settled state")
	panel.set_progress(-1.0)
	assert_almost_eq(panel.scale.x, panel.start_scale, 0.001, "t < 0 clamps to the start state")
