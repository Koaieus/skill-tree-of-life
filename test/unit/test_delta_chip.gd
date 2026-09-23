extends GutTest

## #901 — DeltaChip formats the delta at the row's precision (decimals +
## suffix passed in by the caller) instead of always truncating to int, and
## the calling row skips the pop entirely when the *rendered* magnitude is
## zero. Sign stays arithmetic (`%+.*f`) so a negative delta keeps its `-`.

const _CHIP_SCENE := preload("res://ui/gauges/delta_chip.tscn")
const _ATTRIBUTE_ROW_SCENE := preload("res://ui/hud/attributes_panel/attribute_row.tscn")
const _COMBAT_VALUE_ROW_SCENE := preload("res://ui/hud/combat_readout/combat_value_row.tscn")


func test_pop_formats_negative_delta_at_given_precision_with_suffix() -> void:
	var chip: DeltaChip = _CHIP_SCENE.instantiate()
	add_child_autofree(chip)
	chip.pop(-0.02, 2, "%")
	var label: Label = chip.get_node(^"%Label")
	assert_eq(label.text, "▼-0.02%")


func test_pop_default_precision_positive() -> void:
	var chip: DeltaChip = _CHIP_SCENE.instantiate()
	add_child_autofree(chip)
	chip.pop(3.0)
	var label: Label = chip.get_node(^"%Label")
	assert_eq(label.text, "▲+3")


func test_pop_default_precision_negative_keeps_sign() -> void:
	var chip: DeltaChip = _CHIP_SCENE.instantiate()
	add_child_autofree(chip)
	chip.pop(-2.0)
	var label: Label = chip.get_node(^"%Label")
	assert_eq(label.text, "▼-2")


## #729 — a `def` argument lets the colour carry polarity while the arrow/sign
## stay arithmetic truth. `min_damage_taken` is `lower_is_better`, so a -1
## delta (the floor dropping — good) reads GREEN, and a +1 delta reads RED.
func test_pop_with_lower_is_better_def_colours_negative_delta_positive() -> void:
	var chip: DeltaChip = _CHIP_SCENE.instantiate()
	add_child_autofree(chip)
	var def: StatDef = StatRegistry.get_def(&"min_damage_taken")
	chip.pop(-1.0, 0, "", def)
	var label: Label = chip.get_node(^"%Label")
	assert_eq(label.text, "▼-1")
	assert_eq(label.modulate, chip.positive_color)


func test_pop_with_lower_is_better_def_colours_positive_delta_negative() -> void:
	var chip: DeltaChip = _CHIP_SCENE.instantiate()
	add_child_autofree(chip)
	var def: StatDef = StatRegistry.get_def(&"min_damage_taken")
	chip.pop(1.0, 0, "", def)
	var label: Label = chip.get_node(^"%Label")
	assert_eq(label.text, "▲+1")
	assert_eq(label.modulate, chip.negative_color)


func test_pop_with_no_def_keeps_sign_only_colouring() -> void:
	var chip: DeltaChip = _CHIP_SCENE.instantiate()
	add_child_autofree(chip)
	chip.pop(-1.0)
	var label: Label = chip.get_node(^"%Label")
	assert_eq(label.text, "▼-1")
	assert_eq(label.modulate, chip.negative_color)


## #729 acceptance 3 — CombatValueRow.stat_id resolves the def, so a
## min_damage_taken row's floor dropping (3 -> 2, delta -1) reads GREEN.
func test_combat_value_row_with_stat_id_colours_chip_by_polarity() -> void:
	var row: CombatValueRow = _COMBAT_VALUE_ROW_SCENE.instantiate()
	row.stat_id = &"min_damage_taken"
	add_child_autofree(row)
	row.set_value(3.0)
	await get_tree().process_frame
	row.set_value(2.0)
	await get_tree().process_frame
	var chip: DeltaChip = row.get_node(^"%DeltaChip")
	var label: Label = chip.get_node(^"%Label")
	assert_eq(label.text, "▼-1")
	assert_eq(label.modulate, chip.positive_color)


func test_combat_value_row_pops_at_row_precision() -> void:
	var row: CombatValueRow = _COMBAT_VALUE_ROW_SCENE.instantiate()
	row.decimals = 2
	add_child_autofree(row)
	row.set_value(0.08)
	await get_tree().process_frame
	row.set_value(0.06)
	await get_tree().process_frame
	var chip: DeltaChip = row.get_node(^"%DeltaChip")
	var label: Label = chip.get_node(^"%Label")
	assert_eq(label.text, "▼-0.02")


func test_combat_value_row_skips_pop_when_rendered_magnitude_is_zero() -> void:
	var row: CombatValueRow = _COMBAT_VALUE_ROW_SCENE.instantiate()
	row.decimals = 0
	add_child_autofree(row)
	row.set_value(5.0)
	await get_tree().process_frame
	var chip: DeltaChip = row.get_node(^"%DeltaChip")
	var panel: PanelContainer = chip.get_node(^"%Panel")
	var label: Label = chip.get_node(^"%Label")
	var label_before := label.text
	var alpha_before := panel.modulate.a
	row.set_value(5.4)
	await get_tree().process_frame
	assert_eq(label.text, label_before, "label should not change when rendered magnitude is zero")
	assert_eq(panel.modulate.a, alpha_before, "chip should not pop (alpha unchanged) when rendered magnitude is zero")


func test_attribute_row_skips_pop_when_rendered_magnitude_is_zero() -> void:
	var row: AttributeRow = _ATTRIBUTE_ROW_SCENE.instantiate()
	add_child_autofree(row)
	row.set_value(10.0)
	await get_tree().process_frame
	var chip: DeltaChip = row.get_node(^"%DeltaChip")
	var panel: PanelContainer = chip.get_node(^"%Panel")
	var alpha_before := panel.modulate.a
	row.set_value(10.4)
	await get_tree().process_frame
	assert_eq(panel.modulate.a, alpha_before, "chip should not pop when rendered (int) magnitude is zero")


func test_attribute_row_pops_the_difference_of_what_it_displays() -> void:
	# 5.9 -> 6.1 displays "5" -> "6": the chip shows +1, never the raw +0.2
	# that would truncate to "+0" at the row's whole-number precision.
	var row: AttributeRow = _ATTRIBUTE_ROW_SCENE.instantiate()
	add_child_autofree(row)
	row.set_value(5.9)
	await get_tree().process_frame
	row.set_value(6.1)
	await get_tree().process_frame
	var label: Label = row.get_node(^"%DeltaChip").get_node(^"%Label")
	assert_eq(label.text, "▲+1")


## #1051 acceptance 4 — the chip's "this got worse" red is the repo's one
## harmful colour, hoisted to Emissive.HARMFUL, and its value did not move.
func test_negative_color_is_the_hoisted_harmful_constant_unchanged() -> void:
	var chip: DeltaChip = _CHIP_SCENE.instantiate()
	add_child_autofree(chip)
	assert_eq(chip.negative_color, Color(0.95, 0.45, 0.45, 1.0))
	assert_eq(chip.negative_color, Emissive.HARMFUL)
