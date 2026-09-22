extends GutTest

## The valence law (#1049): a modifier's delta is its value's displacement from
## its OP's neutral element, judged through StatDef.is_improvement.
##
## Pins the law itself, MULTIPLY either side of 1, the NEUTRAL/VOLATILE set,
## the two shipped curse fixtures, and the editor guard on a MULTIPLY pool
## whose folded range crosses zero.
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


## `v - 1.0` is a subtraction, so `1.35 - 1.0` is `0.3500000000000001` — the
## law is exact, binary floats are not, and every consumer compares the
## displacement approximately (`is_zero_approx`, `is_improvement`'s sign).
func test_displacement_is_value_minus_one_for_multiply() -> void:
	assert_almost_eq(StatModifier.displacement_from_neutral(StatModifier.Operation.MULTIPLY, 1.35), 0.35, 1e-6)
	assert_almost_eq(StatModifier.displacement_from_neutral(StatModifier.Operation.MULTIPLY, 0.65), -0.35, 1e-6)
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


## Acceptance 2 (#1050): the editor-side guard for the value the law can only
## call VOLATILE. `to_entries` folds MULTIPLY as `1 + magnitude`, so a debuff
## pool (negative `unit_value`) deep enough on the V ladder mints a
## sign-flipping multiplier. `test_pool_scoping.gd` sweeps the SHIPPED pools'
## warnings; this pins the rule itself on a pool authored to trip it.
func test_a_sign_flipping_multiply_pool_warns() -> void:
	var pool := StatPool.new()
	pool.stat_id = &"armor"
	pool.operation = StatModifier.Operation.MULTIPLY
	pool.unit_value = -0.2
	pool.max_tier = 3
	var warnings := "\n".join(pool._get_configuration_warnings())
	assert_string_contains(warnings, "sign-flipping multiplier")


func test_a_normal_multiply_pool_does_not_warn() -> void:
	var pool := StatPool.new()
	pool.stat_id = &"armor"
	pool.operation = StatModifier.Operation.MULTIPLY
	pool.unit_value = 0.05
	var warnings := "\n".join(pool._get_configuration_warnings())
	assert_false(warnings.contains("sign-flipping"), warnings)
