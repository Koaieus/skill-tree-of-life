extends GutTest
## v4 StatPool conformance for constitution.tres (#321 wave 1).
const _PACK := preload("res://procgen/pools/constitution.tres")
const _GP := preload("res://procgen/graph_procgen.gd")

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func test_pack_loads_as_statpack() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	assert_not_null(p)
	assert_eq(p.archetype_stat, &"constitution")
	assert_true(p.pools.size() > 0)


func test_constitution_pool_values() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	for sp in p.pools:
		var pp: StatPool = sp as StatPool
		if pp.stat_id == &"constitution" and pp.operation == StatModifier.Operation.ADD_BASE:
			assert_eq(pp.unit_value, 2.0)
			assert_eq(pp.min_tier, 1)
			assert_eq(pp.max_tier, 4)
			assert_eq(pp.to_entries().size(), 4)
			var e0 = pp.to_entries()[0]
			assert_almost_eq((e0.value_range.x + e0.value_range.y) / 2.0, 2.0, 0.001)


func test_universal_pools_are_archetype_empty() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	for sp in p.pools:
		var pp: StatPool = sp as StatPool
		if pp.stat_id == &"node_health" or pp.stat_id == &"armor":
			assert_eq(pp.archetype_stat, &"", "pool %s should be universal" % String(pp.stat_id))


## The CON pack's INT debuff — asserts the pool's SHAPE, not its magnitudes.
##
## This used to pin `unit_value == -5.0` and `max_tier == 1` outright, so the
## 2026-08-07 playtest retune (softer per-tier bite, -5% → -2%, spread across
## three tiers instead of stopping at one) failed it on three lines while
## nothing was actually wrong. A balance knob under a `.tres` is meant to move;
## a test that pins its value converts every retune into a red suite and teaches
## people to edit the number until it goes green.
##
## What must stay true regardless of tuning: it is a DEBUFF (negative unit
## value, negative cost so the draw pays you for taking it), and it ladders one
## entry per tier.
func test_intelligence_debuff_pool() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	var found := false
	for sp in p.pools:
		var pp: StatPool = sp as StatPool
		if pp.stat_id == &"intelligence" and pp.operation == StatModifier.Operation.INCREASE:
			found = true
			assert_lt(pp.unit_value, 0.0, "the INT pool in the CON pack is a debuff")
			assert_gte(pp.max_tier, 1, "reachable on at least one tier")
			assert_eq(pp.to_entries().size(), pp.max_tier,
					"one entry per tier up to max_tier")
			for e in pp.to_entries():
				assert_lt(e.cost, 0, "a debuff refunds cost rather than charging it")
	assert_true(found, "the CON pack still carries an INT debuff pool at all")


func test_constitution_draw_only_emits_pack_stat_ids() -> void:
	var pool_set := ModifierPoolSet.new()
	pool_set.packs = [_PACK.duplicate(true)]
	var primary := &"constitution"
	var ids: Array = []
	for seed_value in range(1, 25):
		var mods: Array = _GP._roll_modifiers_v4(pool_set, [], primary, primary, [] as Array[StringName], Vector2.ZERO, 0, 8, _rng(seed_value))
		for m in mods:
			if not (m.stat_id in ids):
				ids.append(m.stat_id)
	for sid in ids:
		assert_true(sid in [&"constitution", &"node_health", &"armor", &"intelligence"], "unexpected: %s" % String(sid))
