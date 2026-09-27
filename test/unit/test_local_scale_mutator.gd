extends GutTest

## LocalScaleMutator on a bare NodeState — no SkillNode, no board: the law
## alone. The node-composed behaviour is pinned by test_local_scaling.gd.


func _multiply(value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = &"strength"
	m.operation = StatModifier.Operation.MULTIPLY
	m.value = value
	return m


func test_multiply_scales_up_and_round_trips_exactly_on_a_bare_state() -> void:
	var s := NodeState.new()
	var m := _multiply(1.5)
	s.local_modifiers.append(m)
	var mutator := LocalScaleMutator.new()
	mutator.apply(s, 1, 3)
	assert_eq(m.value, 2.5, "MULTIPLY adds the growth part: 1 + 0.5 x 3")
	mutator.apply(s, 3, 1)
	assert_eq(m.value, 1.5, "and 3 -> 1 restores the authored value exactly")


func test_entity_scoped_modifiers_scale_too_without_an_owner() -> void:
	var s := NodeState.new()
	var m := _multiply(2.0)
	s.modifiers.append(m)
	LocalScaleMutator.new().apply(s, 1, 2)
	assert_eq(m.value, 3.0, "1 + 1 x 2 — no contribution board needed for the value law")
