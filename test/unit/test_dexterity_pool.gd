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
## Shape of the pack's own DEX ladder, not its magnitudes (#719): the owner
## tunes `unit_value` / `range_floor` / the tier span (b3975d8 and again
## 2026-09-04 did), and a literal pin goes red on every tune while blaming the
## pool. What is load-bearing is the mechanism the authored fields feed —
## pinned on a hand-built pool in test_pool_seed_values.gd — and that THIS pack
## authors a DEX ADD_BASE pool that mechanism can act on.
func test_dexterity_pool_shape() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	var found := false
	for sp in p.pools:
		var pp: StatPool = sp as StatPool
		if pp.stat_id != &"dexterity" or pp.operation != StatModifier.Operation.ADD_BASE:
			continue
		found = true
		assert_gt(pp.unit_value, 0.0, "DEX is a positive ladder")
		var entries := pp.to_entries()
		assert_eq(entries.size(), pp.max_tier - pp.min_tier + 1, "one entry per offered tier")
		for i in entries.size():
			var tier := pp.min_tier + i
			var r: Vector2 = entries[i].value_range
			assert_true(r.x <= r.y, "T%d rolls a non-inverted range (%s)" % [tier, r])
		if not pp.value_overrides.has(pp.min_tier):
			# #628: the first tier's low is the authored floor (or unit_value
			# when none is authored), its high is unit_value x V[0] = unit_value.
			var e0: Vector2 = entries[0].value_range
			assert_almost_eq(e0.x, pp._effective_floor(), 0.001, "T1 low = M")
			assert_almost_eq(e0.y, pp.unit_value * TierLadder.value(1), 0.001, "T1 high = unit x V[0]")
	assert_true(found, "the dexterity pack must carry a DEX ADD_BASE pool at all")
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


## #718: the DEX pack's own curse — "the duelist wears no plate."
##
## Shape only, no magnitudes (#719). Two things are load-bearing and neither is
## a tuning knob:
##
## 1. **INCREASE, not ADD_BASE.** `armor`'s base is 0 and procgen writes
##    `SkillNode.modifiers`, which is ENTITY-scoped (skill_node.gd's "the
##    complement of `_local_modifiers` (entity-scoped)") — so a flat armor
##    curse would mint unbounded *negative* armor across the whole territory,
##    and `Mitigation.compute` floors at min_damage_taken rather than capping,
##    i.e. every hit would land at `raw + N`. As an INCREASE it scales down the
##    armor you actually accumulated: proportional, self-limiting, and free
##    until you own armor at all.
## 2. **Negative at both ends.** A downside pool that can roll a buff is not a
##    downside pool.
func test_armor_curse_is_a_self_limiting_downside() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	var found := false
	for sp in p.pools:
		var pp: StatPool = sp as StatPool
		if pp.stat_id != &"armor":
			continue
		found = true
		assert_eq(pp.operation, StatModifier.Operation.INCREASE,
				"the armor curse must be INCREASE — ADD_BASE would mint unbounded negative armor from a zero base")
		assert_lt(pp.unit_value, 0.0, "the armor pool in the DEX pack is a downside pool")
		for e in pp.to_entries():
			assert_lt(e.value_range.y, 0.0, "every tier stays negative at BOTH ends")
			assert_gt(e.cost, 0, "cost is always positive (#637)")
	assert_true(found, "the dexterity pack must carry an armor curse at all")
