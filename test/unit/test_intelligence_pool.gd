extends GutTest
## v4 StatPool conformance for intelligence.tres (#321 wave 1).
const _PACK := preload("res://procgen/pools/intelligence.tres")
const _GP := preload("res://procgen/graph_procgen.gd")
func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new(); r.seed = s; return r
func test_pack_loads_as_statpack() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	assert_not_null(p); assert_eq(p.archetype_stat, &"intelligence")
	assert_true(p.pools.size() > 0)
func test_intelligence_pool_values() -> void:
	# Content invariant, NOT a value pin (#719). The magnitudes here are the
	# owner's to tune between balance passes; pinning them turned a deliberate
	# tuning pass red without catching anything (#717). Formula conformance for
	# whatever this pool authors is swept in test_pool_range_bounds.gd, the
	# ladder itself is pinned on hand-built pools in test_pool_seed_values.gd,
	# and unintended content drift is the procgen goldens' job.
	var p: StatPack = _PACK.duplicate(true) as StatPack
	var found := false
	for sp in p.pools:
		var pp: StatPool = sp as StatPool
		if pp.stat_id == &"intelligence" and pp.operation == StatModifier.Operation.ADD_BASE:
			found = true
			assert_eq(pp.to_entries().size(), pp.max_tier - pp.min_tier + 1,
					"intelligence.addb: one entry per offered tier")
	assert_true(found, "the pack must carry a intelligence addb pool at all")
func test_mana_pool_values() -> void:
	# Content invariant, NOT a value pin (#719). The magnitudes here are the
	# owner's to tune between balance passes; pinning them turned a deliberate
	# tuning pass red without catching anything (#717). Formula conformance for
	# whatever this pool authors is swept in test_pool_range_bounds.gd, the
	# ladder itself is pinned on hand-built pools in test_pool_seed_values.gd,
	# and unintended content drift is the procgen goldens' job.
	var p: StatPack = _PACK.duplicate(true) as StatPack
	var found := false
	for sp in p.pools:
		var pp: StatPool = sp as StatPool
		if pp.stat_id == &"mana" and pp.operation == StatModifier.Operation.ADD_BASE:
			found = true
			assert_eq(pp.to_entries().size(), pp.max_tier - pp.min_tier + 1,
					"mana.addb: one entry per offered tier")
	assert_true(found, "the pack must carry a mana addb pool at all")
func test_draw_only_emits_pack_stat_ids() -> void:
	var pool_set := ModifierPoolSet.new()
	pool_set.packs = [_PACK.duplicate(true)]
	var ids: Array = []
	for seed_value in range(1, 25):
		var mods: Array = _GP._roll_modifiers_v4(pool_set, [], &"intelligence", &"intelligence", [] as Array[StringName], Vector2.ZERO, 0, 8, _rng(seed_value))
		for m in mods: if not (m.stat_id in ids): ids.append(m.stat_id)
	# Every rolled stat_id must be one this pack owns — read OFF the pack, not
	# from a hand-listed trio. The literal list went stale the moment ef67e82
	# gave INT a cross-archetype `node_health +%` pool: the content change was
	# deliberate and the test failed anyway, blaming the roll for a fact about
	# the fixture. Derived, it asserts what its name says.
	var owned: Array[StringName] = []
	for sp in (pool_set.packs[0] as StatPack).pools:
		var sid_owned := (sp as StatPool).stat_id
		if not (sid_owned in owned): owned.append(sid_owned)
	assert_true(owned.size() > 1, "fixture: the pack must own more than one stat for this to bite")
	for sid in ids: assert_true(sid in owned, "unexpected stat_id rolled: %s (pack owns %s)" % [String(sid), owned])
