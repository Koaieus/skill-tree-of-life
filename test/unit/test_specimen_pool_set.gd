extends GutTest

## Specimen pack loads, flattens per-node, and the negative-INCREASE clamp
## on the stat pipeline behaves as designed (stat zeros at sum ≤ −100%).
## v4 (#321): 7 StatPacks (6 archetypes + mobility universal), strength
## ADD_BASE/INCREASE/MULTIPLY + per-archetype stat portfolios, universal
## pools (constitution's node_health/armor + the intelligence debuff +
## mobility's movement/deallocation) drawn by every node.

const _SET := preload("res://procgen/pools/specimen_pool_set.tres")
const _GP := preload("res://procgen/graph_procgen.gd")


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func test_specimen_loads_all_seven_packs() -> void:
	var set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	assert_eq(set.packs.size(), 7, "expected 7 packs (6 archetype + mobility universal)")
	var arch_ids: Array[StringName] = []
	for p in set.packs:
		arch_ids.append(p.archetype_stat)
	for a in [&"strength", &"dexterity", &"intelligence", &"wisdom", &"perception", &"constitution"]:
		assert_true(a in arch_ids, "%s pack present" % String(a))
	# mobility is the universal pack (archetype_stat == &"")
	assert_true(&"" in arch_ids, "mobility pack (universal) present")


func test_specimen_flatten_for_strength_node_returns_strength_plus_universal() -> void:
	var set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	var primary := set.flatten_for_node(&"strength")
	assert_true(primary.size() > 0)
	var stat_ids: Array[StringName] = []
	for e in primary:
		if not e.stat_id in stat_ids:
			stat_ids.append(e.stat_id)
	assert_true(&"strength" in stat_ids, "strength pools drawn for a STR node")
	# Universal pools (node_health, armor, movement_points, deallocation_points,
	# intelligence debuff) are drawn by every node.
	assert_true(&"movement_points" in stat_ids, "universal movement_points drawn for a STR node")
	assert_true(&"node_health" in stat_ids, "universal node_health drawn for a STR node")
	assert_true(&"armor" in stat_ids, "universal armor drawn for a STR node")
	# Off-archetype PRIMARY pools (dexterity, intelligence, …) are NOT drawn —
	# D7 removed the off-archetype phase.
	assert_false(&"dexterity" in stat_ids, "dexterity is off-archetype and must NOT be drawn by a STR node (D7)")
	assert_false(&"wisdom" in stat_ids, "wisdom is off-archetype and must NOT be drawn by a STR node (D7)")


func test_procgen_draw_occasionally_produces_movement_bonus() -> void:
	# Regression for #41 acceptance: run several draws at a budget matching
	# first_level.tres (base 2..4, field-boosted up to ~16), and confirm
	# movement_points/deallocation_points show up "occasionally" via the
	# universal mobility pack — not forced via an inflated budget.
	var set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	var saw_movement := false
	var saw_dealloc := false
	for seed_value in range(1, 60):
		var rng := _rng(seed_value)
		var mods: Array = _GP._roll_modifiers_v4(
				set, [], &"strength", &"strength", [], Vector2.ZERO, 0, 7, rng)
		for m in mods:
			if m.stat_id == &"movement_points":
				saw_movement = true
			elif m.stat_id == &"deallocation_points":
				saw_dealloc = true
	assert_true(saw_movement, "expected at least one movement_points roll across 59 seeded draws")
	assert_true(saw_dealloc, "expected at least one deallocation_points roll across 59 seeded draws")


func test_universal_debuff_pool_is_drawable_and_refunds_budget() -> void:
	# The intelligence INCREASE debuff (unit -5, cost -1) is universal; over
	# enough draws at a modest budget it should land at least once, producing a
	# negative-INCREASE modifier on intelligence.
	var set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	var saw_int_debuff := false
	for seed_value in range(1, 80):
		var rng := _rng(seed_value)
		var mods: Array = _GP._roll_modifiers_v4(
				set, [], &"strength", &"strength", [], Vector2.ZERO, 0, 7, rng)
		for m in mods:
			if m.stat_id == &"intelligence" and m.operation == StatModifier.Operation.INCREASE and m.value < 0.0:
				saw_int_debuff = true
				break
		if saw_int_debuff:
			break
	assert_true(saw_int_debuff, "intelligence debuff pool should land at least once across seeded draws")


func test_value_overrides_stay_under_repo_budget() -> void:
	# D11 guard: the value_overrides escape hatch must not become load-bearing
	# everywhere — if it is, the global V curve is wrong and should change
	# instead. Seed budget ≤ 6 repo-wide; today only crit_chance overrides
	# T3/T4 (2 entries).
	var set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	var total := 0
	var who: Array = []
	for pack in set.packs:
		for sp in pack.pools:
			var p: StatPool = sp as StatPool
			for k in p.value_overrides.keys():
				total += 1
				who.append("%s/%s T%d" % [String(pack.archetype_stat), String(p.stat_id), int(k)])
	assert_true(total <= 6, "value_overrides repo-wide budget ≤ 6 (D11); found %d: %s" % [total, str(who)])
	assert_true(total >= 1, "at least the crit_chance overrides should exist")


func test_pipeline_clamps_negative_increase_below_minus_100() -> void:
	# Standalone unit-test for the modifier_bins clamp. Build a board with
	# strength=10, stack INCREASE = -120%. Effective value should be 0.
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