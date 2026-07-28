extends GutTest

## Tooltip V2 (#159, #303): FanPanel wraps whichever skin Control is hand-placed
## as its first child (GlassPanel/HoloPanel — swap by editing the child, per
## #215's "which packed scene" decision, not a runtime enum) and forwards a
## single `glow` knob per skin type. Since #303, FanPanel is a peer of
## FanTrace: a readable `progress` plus self-driven `play_in()` / `play_out()
## -> Tween`. See docs/domain/tooltip-fan.md.

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


func test_progress_zero_parks_at_start_scale_and_hidden() -> void:
	var panel := _make()
	await get_tree().process_frame
	panel.start_scale = 0.8
	panel.progress = 0.0
	assert_almost_eq(panel.scale.x, 0.8, 0.001)
	assert_almost_eq(panel.modulate.a, 0.0, 0.001)


func test_progress_one_settles_at_full_scale_and_visible() -> void:
	var panel := _make()
	await get_tree().process_frame
	panel.progress = 1.0
	assert_almost_eq(panel.scale.x, 1.0, 0.001)
	assert_almost_eq(panel.modulate.a, 1.0, 0.001)


func test_progress_clamps_out_of_range_input() -> void:
	var panel := _make()
	await get_tree().process_frame
	panel.progress = 2.0
	assert_almost_eq(panel.modulate.a, 1.0, 0.001, "t > 1 clamps to the settled state")
	panel.progress = -1.0
	assert_almost_eq(panel.scale.x, panel.start_scale, 0.001, "t < 0 clamps to the start state")


# --- self-driven play_in / play_out (#303) -----------------------------------

func test_play_in_returns_a_running_tween_and_settles_progress_at_one() -> void:
	var panel := _make()
	await get_tree().process_frame
	panel.panel_unfurl_duration = 0.1
	var tw := panel.play_in()
	assert_not_null(tw, "play_in returns its Tween for sequencing")
	assert_true(tw.is_valid(), "the unfurl tween is live")
	tw.custom_step(1000.0) # force it to completion
	assert_almost_eq(panel.progress, 1.0, 0.001, "play_in settles progress at 1.0")


func test_play_out_returns_a_running_tween_and_settles_progress_at_zero() -> void:
	var panel := _make()
	await get_tree().process_frame
	panel.progress = 1.0
	panel.panel_fade_duration = 0.1
	var tw := panel.play_out()
	assert_not_null(tw)
	assert_true(tw.is_valid())
	tw.custom_step(1000.0)
	assert_almost_eq(panel.progress, 0.0, 0.001, "play_out settles progress at 0.0")


func test_play_out_scales_duration_by_its_own_progress() -> void:
	var panel := _make()
	await get_tree().process_frame
	panel.panel_fade_duration = 0.2
	panel.progress = 0.3 # expected duration ~= 0.2 * 0.3 = 0.06s
	var tw := panel.play_out()
	tw.custom_step(0.03) # half of the ~0.06s leg: must not be done yet
	assert_gt(panel.progress, 0.0, "a 0.3-progress leg takes noticeably longer than a near-zero one")
	tw.custom_step(0.06) # well past 0.06s total: must be settled now
	assert_almost_eq(panel.progress, 0.0, 0.001, "the scaled leg completes at ~30% of the full duration")


func test_play_out_from_zero_progress_floors_at_a_near_instant_duration() -> void:
	var panel := _make()
	await get_tree().process_frame
	panel.panel_fade_duration = 1.0 # raw scale (duration * progress) would be 0.0
	panel.progress = 0.0
	var tw := panel.play_out()
	tw.custom_step(0.03) # the ~0.03s floor: must complete within it
	assert_almost_eq(panel.progress, 0.0, 0.001, "a zero-progress leg still completes near-instantly, at the floor")


func test_play_out_from_near_zero_progress_is_floored_not_shorter() -> void:
	var panel := _make()
	await get_tree().process_frame
	panel.panel_fade_duration = 1.0 # raw scale would be 0.01s, well under the ~0.03s floor
	panel.progress = 0.01
	var tw := panel.play_out()
	tw.custom_step(0.02) # under the floor: must NOT have completed yet
	assert_gt(panel.progress, 0.0, "the floor keeps the leg alive past its raw (unfloored) duration")
