extends GutTest

## Specimen pack loads, flattens by phase, and the negative-INCREASE clamp
## on the stat pipeline behaves as designed (stat zeros at sum ≤ −100%).

const _SET := preload("res://procgen/pools/specimen_pool_set.tres")
const _GP := preload("res://procgen/graph_procgen.gd")


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func test_specimen_loads_and_has_expected_packs() -> void:
	var set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	assert_eq(set.packs.size(), 8, "expected 8 packs (5 archetypes + defensive + rare + mobility)")
	var arch_ids: Array[StringName] = []
	for p in set.packs:
		arch_ids.append(p.archetype_stat)
	assert_true(&"strength" in arch_ids)
	assert_true(&"dexterity" in arch_ids)
	assert_true(&"intelligence" in arch_ids)
	assert_true(&"wisdom" in arch_ids)
	assert_true(&"perception" in arch_ids)


func test_specimen_primary_phase_returns_strength_only_for_strength_node() -> void:
	var set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	var primary := set.flatten_for_phase(&"primary", &"strength")
	assert_true(primary.size() > 0)
	for e in primary:
		assert_eq(e.stat_id, &"strength", "primary phase should only return strength entries for STR node")


func test_specimen_defensive_phase_returns_node_health_and_armor() -> void:
	var set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	var defensive := set.flatten_for_phase(&"defensive", &"strength")
	var stat_ids := []
	for e in defensive:
		if not e.stat_id in stat_ids:
			stat_ids.append(e.stat_id)
	assert_true(&"node_health" in stat_ids)
	assert_true(&"armor" in stat_ids)


func test_specimen_defensive_phase_returns_mobility_entries() -> void:
	var set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	var defensive := set.flatten_for_phase(&"defensive", &"strength")
	var movement_values: Array[float] = []
	var dealloc_values: Array[float] = []
	for e in defensive:
		if e.stat_id == &"movement_points":
			movement_values.append(e.value_range.x)
		elif e.stat_id == &"deallocation_points":
			dealloc_values.append(e.value_range.x)
	assert_true(not movement_values.is_empty(), "mobility pack should contribute movement_points entries")
	assert_true(not dealloc_values.is_empty(), "mobility pack should contribute deallocation_points entries")
	for v in movement_values:
		assert_true(v >= 1.0 and v <= 3.0, "movement_points rolls should stay in 1..3")
	for v in dealloc_values:
		assert_true(v >= 1.0 and v <= 3.0, "deallocation_points rolls should stay in 1..3")


func test_procgen_draw_occasionally_produces_movement_bonus() -> void:
	# Regression for #41 acceptance: run several draws at the set's own
	# (realistic) slot-count distribution and a budget matching
	# first_level.tres's budget_policy (base_max=4, boosted up to ~7 by
	# role_bonus/field), and confirm movement_points/deallocation_points show
	# up "occasionally" — not forced via an inflated budget/slot count.
	var set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	var saw_movement := false
	var saw_dealloc := false
	for seed_value in range(1, 60):
		var rng := _rng(seed_value)
		var mods: Array = _GP._roll_modifiers_v3(
				set, [], &"strength", &"strength", [], Vector2.ZERO, 0, 7, rng)
		for m in mods:
			if m.stat_id == &"movement_points":
				saw_movement = true
			elif m.stat_id == &"deallocation_points":
				saw_dealloc = true
	assert_true(saw_movement, "expected at least one movement_points roll across 59 seeded draws")
	assert_true(saw_dealloc, "expected at least one deallocation_points roll across 59 seeded draws")


func test_specimen_rare_phase_has_min_damage_taken() -> void:
	var set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	var rare := set.flatten_for_phase(&"rare", &"strength")
	var saw_mdt := false
	for e in rare:
		if e.stat_id == &"min_damage_taken":
			saw_mdt = true
			# Verify the godly -1 entry is intact.
			assert_almost_eq(e.value_range.x, -1.0, 0.001)
	assert_true(saw_mdt, "rare pack should include min_damage_taken -1 entry")


func test_specimen_int_off_phase_includes_negative_increase_entries() -> void:
	# A STR-primary node's off-phase pulls from intelligence pack. The
	# negative INCREASE tiers should be present (they're standard PRIMARY
	# pool entries, weights unchanged because the INT pack has empty
	# off_phase_op_weights — no suppression).
	var set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	var off := set.flatten_for_phase(&"off", &"strength")
	var saw_negative_inc := false
	for e in off:
		if (e.stat_id == &"intelligence"
				and e.operation == StatModifier.Operation.INCREASE
				and e.value_range.y < 0.0):
			saw_negative_inc = true
	assert_true(saw_negative_inc, "INT off-phase content should include negative INCREASE entries")


func test_pipeline_clamps_negative_increase_below_minus_100() -> void:
	# Standalone unit-test for the modifier_bins clamp. Build a board with
	# strength=10, stack INCREASE = -120%. Effective value should be 0
	# (not negative).
	var board := preload("res://entity/default_entity_board.tres").duplicate(true) as StatBoard
	board.strength.base_value = 10.0
	var m1 := StatModifier.new()
	m1.stat_id = &"strength"
	m1.operation = StatModifier.Operation.INCREASE
	m1.value = -60.0
	var m2 := StatModifier.new()
	m2.stat_id = &"strength"
	m2.operation = StatModifier.Operation.INCREASE
	m2.value = -60.0
	board.add_modifier(m1)
	board.add_modifier(m2)
	# (1 + (-120)/100) would be -0.2 → clamped to 0 → stat reads 0.
	assert_almost_eq(float(board.strength.get_value()), 0.0, 0.001)
