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
	var pool_set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	assert_eq(pool_set.packs.size(), 7, "expected 7 packs (6 archetype + universal)")
	var arch_ids: Array[StringName] = []
	for p in pool_set.packs:
		arch_ids.append(p.archetype_stat)
	for a in [&"strength", &"dexterity", &"intelligence", &"wisdom", &"perception", &"constitution"]:
		assert_true(a in arch_ids, "%s pack present" % String(a))
	# universal.tres is the universal pack (archetype_stat == &"")
	assert_true(&"" in arch_ids, "universal pack present")


func test_specimen_flatten_for_strength_node_returns_strength_plus_universal() -> void:
	var pool_set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	var primary := pool_set.flatten_for_node(&"strength")
	assert_true(primary.size() > 0)
	var stat_ids: Array[StringName] = []
	for e in primary:
		if not e.stat_id in stat_ids:
			stat_ids.append(e.stat_id)
	assert_true(&"strength" in stat_ids, "strength pools drawn for a STR node")
	# Universal pools (node_health, armor, movement_points, deallocation_points)
	# (universal.tres) are drawn by every node. No CURSE is universal — every
	# downside pool sits in its archetype's pack (#718, #751).
	assert_true(&"movement_points" in stat_ids, "universal movement_points drawn for a STR node")
	assert_true(&"node_health" in stat_ids, "universal node_health drawn for a STR node")
	assert_true(&"armor" in stat_ids, "universal armor drawn for a STR node")
	# Off-archetype PRIMARY pools (dexterity, wisdom, …) are NOT drawn — D7
	# removed the off-archetype phase. `intelligence` is deliberately absent
	# from this list: the STR pack's own `intelligence -%` curse targets it, so
	# a STR node legitimately draws an intelligence-stat entry (#718).
	assert_false(&"dexterity" in stat_ids, "dexterity is off-archetype and must NOT be drawn by a STR node (D7)")
	assert_false(&"wisdom" in stat_ids, "wisdom is off-archetype and must NOT be drawn by a STR node (D7)")


## The draw's shape at a budget matching first_level.tres (base 2..4,
## field-boosted up to ~16): a spend-until-broke roll at 7.
const _BAND_BUDGET := 7
const _BAND_SEEDS := 199
## Width of the rate band in binomial standard deviations. Four keeps the
## false-alarm rate per assert well under 1e-4 while still catching a rate
## that moves by a few percent of the whole draw.
const _BAND_SIGMAS := 4.0


## The pick's own distribution — no profiles, no forbid tags.
func _dist(entries: Array[ModifierPoolEntry], remaining: int,
		share: float = GraphProcgenContent.DEFAULT_UNIVERSAL_SHARE) -> Dictionary:
	return _GP._v4_pick_distribution(entries, [], WeightContext.new(), remaining, share)


## Probability that a spend-until-broke draw of `budget` picks `stat_id` at
## least once, computed exactly from the pick's distribution at each remaining
## budget ([method GraphProcgen._v4_pick_distribution], exactly what the draw
## samples). Exact, so the affordability reshaping late in a draw is in the
## expectation rather than in a fudge on the tolerance.
func _expected_presence(entries: Array[ModifierPoolEntry], stat_id: StringName, budget: int) -> float:
	# p_none[r] = P(no `stat_id` pick in a draw that starts with r remaining).
	var p_none: Array[float] = [1.0]
	for r in range(1, budget + 1):
		var d := _dist(entries, r)
		if d.is_empty():
			p_none.append(1.0)
			continue
		var acc := 0.0
		for e: ModifierPoolEntry in d:
			if e.stat_id != stat_id:
				acc += d[e] * p_none[r - e.cost]
		p_none.append(acc)
	return 1.0 - p_none[budget]


func test_procgen_draw_mobility_rate_matches_authored_weights() -> void:
	# Regression for #41 acceptance, sharpened by #975: movement_points and
	# deallocation_points show up at the rate the authored weights (under the
	# universal share) predict — not "at least once", and not via an inflated
	# budget. No percentage is written here; every number is derived.
	var pool_set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	var entries := pool_set.flatten_for_node(&"strength")
	var seen := {&"movement_points": 0, &"deallocation_points": 0}
	for seed_value in range(1, _BAND_SEEDS + 1):
		var mods: Array = _GP._roll_modifiers_v4(
				pool_set, [], &"strength", &"strength", [], Vector2.ZERO, 0, _BAND_BUDGET, _rng(seed_value))
		for sid: StringName in seen.keys():
			for m in mods:
				if m.stat_id == sid:
					seen[sid] += 1
					break
	for sid: StringName in seen.keys():
		var expected := _expected_presence(entries, sid, _BAND_BUDGET)
		var observed := float(seen[sid]) / _BAND_SEEDS
		var tol := _BAND_SIGMAS * sqrt(expected * (1.0 - expected) / _BAND_SEEDS)
		assert_true(expected > 0.0, "%s must be drawable at all on a STR node" % sid)
		assert_almost_eq(observed, expected, tol,
			"%s per-draw rate: expected %.4f, observed %.4f (%d/%d), band ±%.4f"
			% [sid, expected, observed, seen[sid], _BAND_SEEDS, tol])


const _PRIMARIES: Array[StringName] = [&"strength", &"dexterity",
	&"intelligence", &"constitution", &"wisdom", &"perception"]
const _ALL := 1 << 20


## Universal probability mass of one node's pick, every tier affordable.
func _universal_fraction(pool_set: ModifierPoolSet, primary: StringName,
		share: float = GraphProcgenContent.DEFAULT_UNIVERSAL_SHARE) -> float:
	var d := _dist(pool_set.flatten_for_node(primary), _ALL, share)
	var u := 0.0
	for e: ModifierPoolEntry in d:
		if e.universal:
			u += d[e]
	return u


func _throwaway_pack(archetype: StringName, pool_weight: float) -> StatPack:
	var pool := StatPool.new()
	pool.stat_id = &"node_health"
	pool.operation = StatModifier.Operation.MULTIPLY
	pool.pool_weight = pool_weight
	var pack := StatPack.new()
	pack.archetype_stat = archetype
	pack.pools = [pool] as Array[StatPool]
	return pack


func test_universal_share_is_identical_for_every_primary() -> void:
	var pool_set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	for primary in _PRIMARIES:
		assert_almost_eq(_universal_fraction(pool_set, primary),
			GraphProcgenContent.DEFAULT_UNIVERSAL_SHARE, 1e-9,
			"%s: universal share of the pick is the knob, not an accident of pack size" % primary)


func test_appending_a_universal_pool_redistributes_inside_the_share() -> void:
	var pool_set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	var pw_before := 0.0
	for pack in pool_set.packs:
		if pack.archetype_stat == &"":
			for pool: StatPool in pack.pools:
				if pool.admits_subtype(NodeSubtype.regular()):
					pw_before += pool.pool_weight
	var pack := _throwaway_pack(&"", 3.0)
	var key := (pack.pools[0] as StatPool).to_entries(&"")[0].pool_key
	pool_set.packs.append(pack)
	for primary in _PRIMARIES:
		var share := _universal_fraction(pool_set, primary)
		assert_almost_eq(share, GraphProcgenContent.DEFAULT_UNIVERSAL_SHARE, 1e-9,
			"%s: a new universal pool must not grow the universal share" % primary)
		var d := _dist(pool_set.flatten_for_node(primary), _ALL)
		var mine := 0.0
		for e: ModifierPoolEntry in d:
			if e.pool_key == key:
				mine += d[e]
		assert_almost_eq(mine / share, 3.0 / (pw_before + 3.0), 1e-9,
			"%s: the new pool's share within universal is its pool_weight fraction" % primary)


func test_appending_an_archetype_pool_keeps_that_primarys_share() -> void:
	var pool_set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	pool_set.packs.append(_throwaway_pack(&"strength", 5.0))
	for primary in _PRIMARIES:
		assert_almost_eq(_universal_fraction(pool_set, primary),
			GraphProcgenContent.DEFAULT_UNIVERSAL_SHARE, 1e-9,
			"%s: a bigger archetype pack must not starve universal content" % primary)


func test_share_guards() -> void:
	var pool_set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	# share 0 draws no universal entry; share 1 draws nothing else.
	assert_true(_dist(pool_set.flatten_for_node(&"strength"), _ALL, 0.0).size() > 0,
		"share 0 keeps the archetype content")
	assert_almost_eq(_universal_fraction(pool_set, &"strength", 0.0), 0.0, 1e-12)
	assert_almost_eq(_universal_fraction(pool_set, &"strength", 1.0), 1.0, 1e-12)
	# A set with no universal pools: archetype content takes the whole pick.
	var arch_only := ModifierPoolSet.new()
	arch_only.packs = [_throwaway_pack(&"strength", 2.0)] as Array[StatPack]
	var d := _dist(arch_only.flatten_for_node(&"strength"), _ALL)
	var total := 0.0
	for e in d:
		total += d[e]
	assert_almost_eq(total, 1.0, 1e-9, "no universal pools: archetype takes the pick")
	# A primary with no matching pack: its only content is universal — all of it.
	assert_almost_eq(_universal_fraction(pool_set, &"no_such_stat"), 1.0, 1e-9,
		"a pack-less primary still draws universal content, as the whole pick")


func test_strength_pack_intelligence_curse_is_drawable() -> void:
	# The STR pack's `intelligence -%` curse: over enough draws at a modest
	# budget it should land at least once on a STR node, producing a
	# negative-INCREASE modifier on intelligence.
	#
	# Renamed twice. It stopped "refunding budget" in #637 (cost is always
	# positive now), and it stopped being *universal* in #718 — it sits in
	# strength.tres (#751: the pack is the gate), so this draw finds it only because the
	# node's primary IS strength. The old name asserted two things that are no
	# longer true; the behaviour under test is unchanged.
	var pool_set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	var saw_int_debuff := false
	for seed_value in range(1, 80):
		var rng := _rng(seed_value)
		var mods: Array = _GP._roll_modifiers_v4(
				pool_set, [], &"strength", &"strength", [], Vector2.ZERO, 0, 7, rng)
		for m in mods:
			if m.stat_id == &"intelligence" and m.operation == StatModifier.Operation.INCREASE and m.value < 0.0:
				saw_int_debuff = true
				break
		if saw_int_debuff:
			break
	assert_true(saw_int_debuff, "the STR pack's intelligence curse should land at least once across seeded draws")


func test_value_overrides_stay_under_repo_budget() -> void:
	# D11 guard: the value_overrides escape hatch must not become load-bearing
	# everywhere — if it is, the global V curve is wrong and should change
	# instead. Seed budget ≤ 6 repo-wide; today only crit_chance overrides
	# T3/T4 (2 entries).
	var pool_set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	var total := 0
	var who: Array = []
	for pack in pool_set.packs:
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
	var board := preload("res://entity/default_entity_board.tres").duplicate(true) as EntityStatBoard
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

## DoT potency lives on attribute packs (poison→DEX, corruption→STR,
## curse→CON, wither→INT after #1058); a node never rolls a potency its
## archetype does not own, and after #1059 only its BLIGHTED nodes roll it at
## all. Seeded budget-7 draws, the same harness as the mobility test.
func _potency_ids_over_seeded_draws(primary: StringName,
		subtype_id: StringName = &"blight") -> Array[StringName]:
	var pool_set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	var subtype := NodeSubtype.new()
	subtype.id = subtype_id
	var seen: Array[StringName] = []
	for seed_value in range(1, 200):
		var mods: Array = _GP._roll_modifiers_v4(
				pool_set, [], primary, primary, [], Vector2.ZERO, 0, 7, _rng(seed_value),
				{}, subtype)
		for m in mods:
			if String(m.stat_id).ends_with("_potency") and not (m.stat_id in seen):
				seen.append(m.stat_id)
	return seen


func test_dot_potency_rolls_only_on_its_attribute_home() -> void:
	var str_seen := _potency_ids_over_seeded_draws(&"strength")
	assert_true(&"corruption_potency" in str_seen, "corruption_potency rolls on a STR node (seen %s)" % [str_seen])
	assert_false(&"poison_potency" in str_seen, "poison_potency never rolls on a STR node (seen %s)" % [str_seen])
	var dex_seen := _potency_ids_over_seeded_draws(&"dexterity")
	assert_true(&"poison_potency" in dex_seen, "poison_potency rolls on a DEX node (seen %s)" % [dex_seen])
	assert_false(&"corruption_potency" in dex_seen, "corruption_potency never rolls on a DEX node (seen %s)" % [dex_seen])
	# #1059's second key: the same STR node, regular or blessed, rolls none.
	for pole: StringName in [&"regular", &"bless"]:
		assert_eq(_potency_ids_over_seeded_draws(&"strength", pole).size(), 0,
			"a %s STR node rolls no potency at all — potency is the blighted pole" % pole)


func _subtype_ids(pool: StatPool) -> Array[StringName]:
	var out: Array[StringName] = []
	for st in pool.subtypes:
		out.append(st.id)
	out.sort()
	return out


## Shape, never magnitude: every potency pool in the specimen set is
## archetype-scoped and gated to `blight`; every resistance is archetype-scoped
## and gated to `bless` (#1059 — they stopped being universal) and T2..T4 only.
func test_dot_pools_shape() -> void:
	var pool_set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	var potency_count := 0
	var resistance_count := 0
	for pack in pool_set.packs:
		for sp in (pack as StatPack).pools:
			var pp := sp as StatPool
			var sid := String(pp.stat_id)
			if sid.ends_with("_potency"):
				potency_count += 1
				assert_ne(pack.archetype_stat, &"", "%s must have an attribute home" % sid)
				assert_eq(_subtype_ids(pp), [&"blight"] as Array[StringName],
					"%s is the blighted pole and nothing else" % sid)
			elif sid.ends_with("_resistance"):
				resistance_count += 1
				assert_ne(pack.archetype_stat, &"",
					"%s left the universal pile for its family's archetype (#1059)" % sid)
				assert_eq(_subtype_ids(pp), [&"bless"] as Array[StringName],
					"%s is the blessed pole and nothing else" % sid)
				assert_eq(pp.min_tier, 2, "%s never rolls at T1" % sid)
				assert_eq(pp.max_tier, 4, "%s ladders three rungs to T4" % sid)
	assert_eq(potency_count, 5, "five potency pools across the set (four DoTs + PER's blindness)")
	assert_eq(resistance_count, 5, "five resistance pools across the set (four DoTs + PER's blindness)")
