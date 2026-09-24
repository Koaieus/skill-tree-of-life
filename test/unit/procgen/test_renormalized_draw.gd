extends GutTest

## The v4 pick's distribution (`GraphProcgen._v4_pick_distribution`) asserted
## exactly: universal vs archetype by `universal_share`, pool by
## `pool_weight × m̄`, tier by `w_t·m_t` — each renormalized over what is
## drawable at this pick. Default [TierShape] everywhere: tier weights 1, 2, 4, 8.

const _EPS := 1e-9
const _ALL := 1 << 20


## Zeroes or scales every entry of one stat — a whole-pool profile.
class StatMultiplier extends WeightProfile:
	var stat: StringName
	var factor: float
	func _init(s: StringName, f: float) -> void:
		stat = s
		factor = f
	func multiplier_for(entry: ModifierPoolEntry, _c: WeightContext) -> float:
		return factor if entry.stat_id == stat else 1.0


## Scales one tier of one stat — a tier-tag profile.
class TierMultiplier extends WeightProfile:
	var stat: StringName
	var tier_suffix: String
	var factor: float
	func _init(s: StringName, t: int, f: float) -> void:
		stat = s
		tier_suffix = "_t%d" % t
		factor = f
	func multiplier_for(entry: ModifierPoolEntry, _c: WeightContext) -> float:
		return factor if entry.stat_id == stat and String(entry.id).ends_with(tier_suffix) else 1.0


func _pool(stat: StringName, pw: float, max_tier: int = 4, min_tier: int = 1) -> StatPool:
	var p := StatPool.new()
	p.stat_id = stat
	p.pool_weight = pw
	p.min_tier = min_tier
	p.max_tier = max_tier
	return p


func _entries(universal: Array, archetype: Array) -> Array[ModifierPoolEntry]:
	var out: Array[ModifierPoolEntry] = []
	for p: StatPool in universal:
		out.append_array(p.to_entries(&""))
	for p: StatPool in archetype:
		out.append_array(p.to_entries(&"strength"))
	return out


func _dist(entries: Array[ModifierPoolEntry], remaining: int = _ALL,
		profiles: Array[Resource] = [], share: float = 0.2) -> Dictionary:
	var ctx := WeightContext.new()
	ctx.archetype = &"red"
	return GraphProcgen._v4_pick_distribution(entries, profiles, ctx, remaining, share)


func _stat_total(dist: Dictionary, stat: StringName) -> float:
	var s := 0.0
	for e: ModifierPoolEntry in dist:
		if e.stat_id == stat:
			s += dist[e]
	return s


func _tier_p(dist: Dictionary, stat: StringName, t: int) -> float:
	for e: ModifierPoolEntry in dist:
		if e.stat_id == stat and String(e.id).ends_with("_t%d" % t):
			return dist[e]
	return 0.0


func _assert_sums_to_one(dist: Dictionary) -> void:
	var s := 0.0
	for e in dist:
		s += dist[e]
	assert_almost_eq(s, 1.0, _EPS, "distribution sums to 1")


func test_universal_group_takes_its_share_and_pools_split_the_rest() -> void:
	var entries := _entries([_pool(&"armor", 1.0)],
		[_pool(&"a1", 1.0), _pool(&"a2", 2.0), _pool(&"a3", 3.0)])
	var d := _dist(entries)
	_assert_sums_to_one(d)
	assert_almost_eq(_stat_total(d, &"armor"), 0.2, _EPS, "universal tiers sum to universal_share")
	assert_almost_eq(_stat_total(d, &"a1"), 0.8 / 6.0, _EPS)
	assert_almost_eq(_stat_total(d, &"a2"), 0.8 * 2.0 / 6.0, _EPS)
	assert_almost_eq(_stat_total(d, &"a3"), 0.8 * 3.0 / 6.0, _EPS)
	assert_almost_eq(_tier_p(d, &"armor", 1), 0.2 / 15.0, _EPS, "tier by bare tier weight")
	assert_almost_eq(_tier_p(d, &"a3", 4), 0.4 * 8.0 / 15.0, _EPS)


func test_subtype_gated_pool_mass_goes_to_its_siblings_only() -> void:
	var blighted := NodeSubtype.new()
	blighted.id = &"blighted"
	var gated := _pool(&"a2", 2.0)
	gated.subtypes = [blighted] as Array[NodeSubtype]
	var u := StatPack.new()
	u.archetype_stat = &""
	u.pools = [_pool(&"armor", 1.0)] as Array[StatPool]
	var a := StatPack.new()
	a.archetype_stat = &"strength"
	a.pools = [_pool(&"a1", 1.0), gated, _pool(&"a3", 3.0)] as Array[StatPool]
	var set := ModifierPoolSet.new()
	set.packs = [u, a] as Array[StatPack]
	var d := _dist(set.flatten_for_node(&"strength"))
	_assert_sums_to_one(d)
	assert_almost_eq(_stat_total(d, &"a2"), 0.0, _EPS, "gated out")
	assert_almost_eq(_stat_total(d, &"armor"), 0.2, _EPS, "universal total unmoved")
	assert_almost_eq(_stat_total(d, &"a1"), 0.8 / 4.0, _EPS)
	assert_almost_eq(_stat_total(d, &"a3"), 0.8 * 3.0 / 4.0, _EPS)


func test_budget_tail_keeps_pool_mass() -> void:
	var entries := _entries([_pool(&"armor", 2.0, 3), _pool(&"movement_points", 0.6, 2)],
		[_pool(&"a1", 1.0)])
	var d := _dist(entries, 1)
	_assert_sums_to_one(d)
	assert_almost_eq(_stat_total(d, &"armor"), 0.2 * 2.0 / 2.6, _EPS)
	assert_almost_eq(_tier_p(d, &"armor", 1), 0.2 * 2.0 / 2.6, _EPS, "all of it on T1")
	assert_almost_eq(_stat_total(d, &"movement_points"), 0.2 * 0.6 / 2.6, _EPS)
	assert_almost_eq(_stat_total(d, &"a1"), 0.8, _EPS)


func test_unaffordable_pool_drops_and_empty_group_cedes_the_pick() -> void:
	# mv's cheapest tier (T3, cost 4) is out of reach at remaining 3.
	var entries := _entries([_pool(&"armor", 1.0), _pool(&"movement_points", 5.0, 4, 3)],
		[_pool(&"a1", 1.0)])
	var d := _dist(entries, 3)
	_assert_sums_to_one(d)
	assert_almost_eq(_stat_total(d, &"movement_points"), 0.0, _EPS)
	assert_almost_eq(_stat_total(d, &"armor"), 0.2, _EPS, "sibling takes the dropped mass")
	assert_almost_eq(_tier_p(d, &"armor", 1), 0.2 / 3.0, _EPS, "tiers reshaped over T1..T2")
	assert_almost_eq(_tier_p(d, &"armor", 2), 0.2 * 2.0 / 3.0, _EPS)
	var only_mv := _entries([_pool(&"movement_points", 5.0, 4, 3)], [_pool(&"a1", 1.0)])
	var d2 := _dist(only_mv, 3)
	_assert_sums_to_one(d2)
	assert_almost_eq(_stat_total(d2, &"a1"), 1.0, _EPS, "empty universal group cedes the pick")
	var d3 := _dist(_entries([_pool(&"armor", 1.0)], []))
	assert_almost_eq(_stat_total(d3, &"armor"), 1.0, _EPS, "no archetype content: universal takes all")


func test_zeroing_profile_removes_the_pool_and_renormalizes_siblings() -> void:
	var entries := _entries([_pool(&"armor", 1.0), _pool(&"movement_points", 1.0),
		_pool(&"deallocation_points", 2.0)], [_pool(&"a1", 1.0)])
	var profiles: Array[Resource] = [StatMultiplier.new(&"movement_points", 0.0)]
	var d := _dist(entries, _ALL, profiles)
	_assert_sums_to_one(d)
	assert_almost_eq(_stat_total(d, &"movement_points"), 0.0, _EPS)
	assert_almost_eq(_stat_total(d, &"armor"), 0.2 / 3.0, _EPS)
	assert_almost_eq(_stat_total(d, &"deallocation_points"), 0.2 * 2.0 / 3.0, _EPS)


func test_pool_wide_multiplier_scales_pool_mass() -> void:
	var entries := _entries([_pool(&"armor", 1.0), _pool(&"movement_points", 1.0)],
		[_pool(&"a1", 1.0)])
	var profiles: Array[Resource] = [StatMultiplier.new(&"movement_points", 3.0)]
	var d := _dist(entries, _ALL, profiles)
	_assert_sums_to_one(d)
	assert_almost_eq(_stat_total(d, &"movement_points"), 0.2 * 3.0 / 4.0, _EPS)
	assert_almost_eq(_stat_total(d, &"armor"), 0.2 / 4.0, _EPS)
	assert_almost_eq(_tier_p(d, &"movement_points", 4), 0.15 * 8.0 / 15.0, _EPS, "tiers unreshaped")


func test_tier_multiplier_reshapes_tiers_and_moves_mass_by_mean() -> void:
	var entries := _entries([_pool(&"armor", 1.0), _pool(&"movement_points", 1.0)],
		[_pool(&"a1", 1.0)])
	var profiles: Array[Resource] = [TierMultiplier.new(&"armor", 1, 3.0)]
	var d := _dist(entries, _ALL, profiles)
	_assert_sums_to_one(d)
	# m̄(armor) = (3·1 + 2 + 4 + 8) / 15 = 17/15; movement_points' is 1.
	var armor := 0.2 * (17.0 / 15.0) / (17.0 / 15.0 + 1.0)
	assert_almost_eq(_stat_total(d, &"armor"), armor, _EPS)
	assert_almost_eq(_tier_p(d, &"armor", 1), armor * 3.0 / 17.0, _EPS)


func test_nothing_drawable_is_empty_and_the_pick_is_null() -> void:
	var entries := _entries([_pool(&"armor", 1.0)], [_pool(&"a1", 1.0)])
	assert_eq(_dist(entries, 0).size(), 0, "broke node: empty distribution")
	var ctx := WeightContext.new()
	var profiles: Array[Resource] = []
	assert_null(GraphProcgen._v4_weighted_pick(entries, profiles, ctx, 0,
		RandomNumberGenerator.new(), 0.2))
	var d := _dist(entries, 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var picked := GraphProcgen._v4_weighted_pick(entries, profiles, ctx, 1, rng, 0.2)
	assert_true(d.has(picked), "the pick samples the distribution")


func test_to_entries_stamps_the_pool_and_bare_tier_weight() -> void:
	var p := _pool(&"armor", 2.5, 3)
	for e in p.to_entries(&""):
		assert_eq(e.pool_key, &"armor_addb_any", "id minus _t<N>")
		assert_almost_eq(e.pool_weight, 2.5, _EPS)
		assert_true(e.universal)
	for e in p.to_entries(&"strength"):
		assert_false(e.universal)
	assert_almost_eq(p.to_entries(&"")[2].weight, 4.0, _EPS, "bare tier weight, no pool_weight")
