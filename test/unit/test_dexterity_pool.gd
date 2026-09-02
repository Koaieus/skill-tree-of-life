extends GutTest
## v4 StatPool conformance for dexterity.tres (#321 wave 1).
const _PACK := preload("res://procgen/pools/dexterity.tres")
const _GP := preload("res://procgen/graph_procgen.gd")
func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new(); r.seed = s; return r
func test_pack_loads_as_statpack() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	assert_not_null(p); assert_eq(p.archetype_stat, &"dexterity")
	assert_true(p.pools.size() > 0)
func test_dexterity_pool_values() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	for sp in p.pools:
		var pp: StatPool = sp as StatPool
		if pp.stat_id == &"dexterity" and pp.operation == StatModifier.Operation.ADD_BASE:
			assert_eq(pp.unit_value, 3.0)
			assert_eq(pp.range_floor, 1.0)
			assert_eq(pp.min_tier, 1); assert_eq(pp.max_tier, 4)
			assert_eq(pp.to_entries().size(), 4)
			# b3975d8 re-tuned this pool (unit 2 → 3) and authored an explicit
			# `range_floor` of 1.0, so T1 is no longer the zero-width fixed
			# point the default M=unit_value used to make it (#628): its high
			# is still unit*V[0] = 3*1 = 3, but its low is now M = 1.
			var e0 := pp.to_entries()[0]
			assert_almost_eq(e0.value_range.x, 1.0, 0.001, "T1 low = M (authored range_floor)")
			assert_almost_eq(e0.value_range.y, 3.0, 0.001, "T1 high = unit x V[0]")
func test_crit_chance_pool_uses_the_override_escape_hatch() -> void:
	# Content invariant, not a value pin (#719). What matters about this pool
	# is that it is the repo's exemplar of the `value_overrides` escape hatch
	# (#321 D11) — the crit ladder is deliberately steeper than the global V
	# curve — and that each override lands as a zero-width fixed point at its
	# own tier (#629, "bypassing the roll entirely"). The override MAGNITUDES
	# are the owner's to tune; the mechanism is pinned on a hand-built pool in
	# test_pool_seed_values.gd, and the repo-wide override budget (<= 6, D11)
	# is guarded by test_specimen_pool_set.gd.
	var p: StatPack = _PACK.duplicate(true) as StatPack
	var found := false
	for sp in p.pools:
		var pp: StatPool = sp as StatPool
		if pp.stat_id == &"crit_chance" and pp.operation == StatModifier.Operation.INCREASE:
			found = true
			assert_false(pp.value_overrides.is_empty(),
					"crit_chance is the override exemplar — it must author at least one")
			var entries := pp.to_entries()
			assert_eq(entries.size(), pp.max_tier - pp.min_tier + 1, "one entry per offered tier")
			for i in entries.size():
				var tier := pp.min_tier + i
				if pp.value_overrides.has(tier):
					assert_almost_eq(entries[i].value_range.x, entries[i].value_range.y, 0.001,
							"an overridden tier (T%d) is a zero-width fixed point" % tier)
					assert_almost_eq(entries[i].value_range.y, float(pp.value_overrides[tier]), 0.001,
							"T%d high == its override" % tier)
	assert_true(found, "the dexterity pack must carry a crit_chance INCREASE pool at all")


func test_draw_only_emits_pack_stat_ids() -> void:
	var pool_set := ModifierPoolSet.new()
	pool_set.packs = [_PACK.duplicate(true)]
	var ids: Array = []
	for seed_value in range(1, 25):
		var mods: Array = _GP._roll_modifiers_v4(pool_set, [], &"dexterity", &"dexterity", [] as Array[StringName], Vector2.ZERO, 0, 8, _rng(seed_value))
		for m in mods: if not (m.stat_id in ids): ids.append(m.stat_id)
	# every rolled stat_id must be one this pack owns
	# Every rolled stat_id must be one this pack owns — read OFF the pack, not
	# a hand-listed set (#719). A literal list goes stale the moment a pool is
	# added to the pack: the content change is deliberate and the test fails
	# anyway, blaming the roll for a fact about the fixture. Derived, it
	# asserts what its name says — no cross-pack leakage.
	var owned: Array[StringName] = []
	for sp in (pool_set.packs[0] as StatPack).pools:
		var sid_owned := (sp as StatPool).stat_id
		if not (sid_owned in owned): owned.append(sid_owned)
	for sid in ids: assert_true(sid in owned, "unexpected stat_id rolled: %s (pack owns %s)" % [String(sid), owned])
