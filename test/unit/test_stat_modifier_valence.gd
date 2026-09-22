extends GutTest

## The valence law (#1049): a modifier's delta is its value's displacement from
## its OP's neutral element, judged through StatDef.is_improvement.
##
## Every test here is pending() against the stub in stat_modifier.gd — the
## drone's first commit deletes the pending() lines and sees these go RED.
## The two fixtures are live shipped content (procgen/pools/constitution.tres):
## `dexterity INCREASE -3` is a bane, `min_damage_taken ADD_BASE -1` is a boon.
## Same negative sign, opposite valence — the pair this law exists for.


func _mod(op: StatModifier.Operation, v: float, id: StringName) -> StatModifier:
	var m := StatModifier.new()
	m.operation = op
	m.value = v
	m.stat_id = id
	return m


func test_displacement_is_the_value_for_additive_ops() -> void:
	assert_eq(StatModifier.displacement_from_neutral(StatModifier.Operation.ADD_BASE, 4.0), 4.0)
	assert_eq(StatModifier.displacement_from_neutral(StatModifier.Operation.INCREASE, -3.0), -3.0)


func test_displacement_is_value_minus_one_for_multiply() -> void:
	assert_eq(StatModifier.displacement_from_neutral(StatModifier.Operation.MULTIPLY, 1.35), 0.35)
	assert_eq(StatModifier.displacement_from_neutral(StatModifier.Operation.MULTIPLY, 0.65), -0.35)
	assert_eq(StatModifier.displacement_from_neutral(StatModifier.Operation.MULTIPLY, 1.0), 0.0)


func test_set_has_no_neutral_element_and_yields_nan() -> void:
	assert_true(is_nan(StatModifier.displacement_from_neutral(StatModifier.Operation.SET, 13.0)))


func test_the_two_shipped_curse_fixtures_read_opposite_ways() -> void:
	assert_eq(_mod(StatModifier.Operation.INCREASE, -3.0, &"dexterity").valence(),
			StatModifier.Valence.BANE)
	assert_eq(_mod(StatModifier.Operation.ADD_BASE, -1.0, &"min_damage_taken").valence(),
			StatModifier.Valence.BOON)


func test_multiply_valence_follows_the_side_of_one() -> void:
	assert_eq(_mod(StatModifier.Operation.MULTIPLY, 1.35, &"armor").valence(),
			StatModifier.Valence.BOON)
	assert_eq(_mod(StatModifier.Operation.MULTIPLY, 0.65, &"armor").valence(),
			StatModifier.Valence.BANE)
	assert_eq(_mod(StatModifier.Operation.MULTIPLY, 0.65, &"min_damage_taken").valence(),
			StatModifier.Valence.BOON)


func test_neutral_and_volatile() -> void:
	assert_eq(_mod(StatModifier.Operation.MULTIPLY, 1.0, &"armor").valence(),
			StatModifier.Valence.NEUTRAL)
	assert_eq(_mod(StatModifier.Operation.ADD_BASE, 0.0, &"armor").valence(),
			StatModifier.Valence.NEUTRAL)
	assert_eq(_mod(StatModifier.Operation.SET, 13.0, &"armor").valence(),
			StatModifier.Valence.VOLATILE)
	assert_eq(_mod(StatModifier.Operation.MULTIPLY, -1.0, &"armor").valence(),
			StatModifier.Valence.VOLATILE)
