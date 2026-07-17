extends GutTest

## Tooltip V2 Phase 0 (#159): HpReadout wraps the shared LabeledProgressBar
## behind set_hp() + a placement enum. Assert (a) each placement mode
## produces visibly distinct layout state, and (b) set_hp() tints using the
## EXISTING node-HP red->green ramp from SkillNodeTooltip._populate_hp(),
## replicated exactly: Color.from_hsv(lerpf(0.0, 0.33, ratio), 0.9, 1.0).

const _SCENE := preload("res://ui/tooltip_fan/hp_readout.tscn")


func _make() -> HpReadout:
	var readout := _SCENE.instantiate() as HpReadout
	add_child(readout)
	autofree(readout)
	return readout


func _layout_signature(readout: HpReadout) -> Dictionary:
	return {
		"min_size": readout.custom_minimum_size,
		"bar_size": readout._bar.size,
		"bar_label_visible": readout._bar.label.visible,
		"caption_visible": readout._caption.visible,
	}


func test_instantiates_successfully_for_every_placement() -> void:
	for p in [HpReadout.Placement.HEADER, HpReadout.Placement.ABOVE,
			HpReadout.Placement.CHIP, HpReadout.Placement.RING]:
		var readout := _make()
		readout.placement = p
		await get_tree().process_frame
		assert_not_null(readout, "placement %s should instantiate cleanly" % p)


func test_default_placement_is_header() -> void:
	var readout := _make()
	await get_tree().process_frame
	assert_eq(readout.placement, HpReadout.Placement.HEADER)


func test_all_four_placements_yield_distinct_layout_state() -> void:
	var signatures: Array[Dictionary] = []
	for p in [HpReadout.Placement.HEADER, HpReadout.Placement.ABOVE,
			HpReadout.Placement.CHIP, HpReadout.Placement.RING]:
		var readout := _make()
		readout.placement = p
		await get_tree().process_frame
		signatures.append(_layout_signature(readout))

	for i in range(signatures.size()):
		for j in range(i + 1, signatures.size()):
			assert_ne(signatures[i], signatures[j],
				"placement %d and %d produced identical layout state" % [i, j])


func test_header_is_horizontal_with_inline_label_and_full_width_bar() -> void:
	var readout := _make()
	readout.placement = HpReadout.Placement.HEADER
	await get_tree().process_frame
	assert_true(readout._bar.label.visible, "HEADER shows the bar's inline label")
	assert_false(readout._caption.visible, "HEADER has no separate above-caption")
	assert_almost_eq(readout._bar.size.x, readout.custom_minimum_size.x, 0.01,
		"HEADER bar should span the full width")


func test_above_stacks_caption_over_a_thinner_bar() -> void:
	var readout := _make()
	readout.placement = HpReadout.Placement.ABOVE
	await get_tree().process_frame
	assert_true(readout._caption.visible, "ABOVE shows a separate caption label")
	assert_false(readout._bar.label.visible, "ABOVE hides the bar's own inline label")
	assert_true(readout._bar.position.y > readout._caption.position.y,
		"ABOVE bar must sit below the caption")


func test_chip_is_compact_with_overlaid_text() -> void:
	var readout := _make()
	readout.placement = HpReadout.Placement.CHIP
	await get_tree().process_frame
	assert_true(readout._bar.label.visible, "CHIP overlays cur/max on the bar itself")
	assert_true(readout.custom_minimum_size.x < 100.0, "CHIP should be minimal-width")


func test_ring_is_small_and_square_ish() -> void:
	var readout := _make()
	readout.placement = HpReadout.Placement.RING
	await get_tree().process_frame
	assert_true(readout.custom_minimum_size.x < 60.0, "RING should be a small footprint")
	assert_true(readout.custom_minimum_size.y < 20.0, "RING should be a small footprint")


func test_set_hp_zero_current_tints_full_red() -> void:
	var readout := _make()
	await get_tree().process_frame
	readout.set_hp(0.0, 100.0)
	assert_eq(readout.get_tint(), Color.from_hsv(0.0, 0.9, 1.0))
	assert_eq(readout._bar.self_modulate, Color.from_hsv(0.0, 0.9, 1.0))


func test_set_hp_full_current_tints_full_green() -> void:
	var readout := _make()
	await get_tree().process_frame
	readout.set_hp(100.0, 100.0)
	assert_eq(readout.get_tint(), Color.from_hsv(0.33, 0.9, 1.0))
	assert_eq(readout._bar.self_modulate, Color.from_hsv(0.33, 0.9, 1.0))


func test_set_hp_updates_label_text() -> void:
	var readout := _make()
	await get_tree().process_frame
	readout.set_hp(42.0, 100.0)
	assert_eq(readout._bar.label.text, "42/100")
