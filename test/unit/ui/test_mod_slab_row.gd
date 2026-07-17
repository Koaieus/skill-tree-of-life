extends GutTest

## Tooltip V2 (epic #159 Phase 0) — glass-slab row acceptance test.
## Covers: per-operator text formatting + tint (bind), and the staggered
## entry delay schedule (play_entry), without awaiting tween playback.

const _SCENE := preload("res://ui/tooltip_fan/mod_slab_row.tscn")

const _RED := Color(0.85, 0.30, 0.30)
const _GREEN := Color(0.32, 0.78, 0.45)
const _BLUE := Color(0.29, 0.59, 1.0)
const _PURPLE := Color(0.69, 0.40, 0.97)
const _GOLD := Color(0.90, 0.73, 0.27)


func _make_modifier(op: StatModifier.Operation, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.operation = op
	m.value = value
	return m


func test_add_base_formats_and_tints() -> void:
	var row := _SCENE.instantiate()
	add_child_autofree(row)
	row.bind(_make_modifier(StatModifier.Operation.ADD_BASE, 4.0), "stat")
	assert_eq(row._label.text, "+4 stat")
	assert_eq(row.operator_tint, _GREEN)


func test_increase_formats_and_tints() -> void:
	var row := _SCENE.instantiate()
	add_child_autofree(row)
	row.bind(_make_modifier(StatModifier.Operation.INCREASE, 20.0), "stat")
	assert_eq(row._label.text, "+20% stat")
	assert_eq(row.operator_tint, _BLUE)


func test_multiply_formats_and_tints() -> void:
	var row := _SCENE.instantiate()
	add_child_autofree(row)
	row.bind(_make_modifier(StatModifier.Operation.MULTIPLY, 1.5), "stat")
	assert_eq(row._label.text, "×1.50 stat")
	assert_eq(row.operator_tint, _PURPLE)


func test_add_bonus_formats_and_tints() -> void:
	var row := _SCENE.instantiate()
	add_child_autofree(row)
	row.bind(_make_modifier(StatModifier.Operation.ADD_BONUS, 5.0), "stat")
	assert_eq(row._label.text, "+5 stat (flat)")
	assert_eq(row.operator_tint, _GOLD)


func test_set_formats_and_tints() -> void:
	var row := _SCENE.instantiate()
	add_child_autofree(row)
	row.bind(_make_modifier(StatModifier.Operation.SET, 13.0), "stat")
	assert_eq(row._label.text, "= 13 stat")
	assert_eq(row.operator_tint, _RED)


func test_negative_value_keeps_its_own_sign() -> void:
	var row := _SCENE.instantiate()
	add_child_autofree(row)
	row.bind(_make_modifier(StatModifier.Operation.ADD_BASE, -3.0), "stat")
	assert_eq(row._label.text, "-3 stat")


func test_play_entry_computes_staggered_delay() -> void:
	var row := _SCENE.instantiate()
	add_child_autofree(row)
	row.play_entry(2, 0.05)
	assert_true(is_equal_approx(row.entry_delay, 0.10))
