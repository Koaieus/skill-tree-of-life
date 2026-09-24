extends GutTest
## v4 StatPool conformance for wisdom.tres (#321 wave 1).
const _PACK := preload("res://procgen/pools/wisdom.tres")
const _GP := preload("res://procgen/graph_procgen.gd")
func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new(); r.seed = s; return r
func test_pack_loads_as_statpack() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	assert_not_null(p); assert_eq(p.archetype_stat, &"wisdom")
	assert_true(p.pools.size() > 0)
func test_wisdom_pool_values() -> void:
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
		if pp.stat_id == &"wisdom" and pp.operation == StatModifier.Operation.ADD_BASE:
			found = true
			assert_eq(pp.to_entries(p.archetype_stat).size(), pp.max_tier - pp.min_tier + 1,
					"wisdom.addb: one entry per offered tier")
	assert_true(found, "the pack must carry a wisdom addb pool at all")
func _flatten(subtype: NodeSubtype) -> Array[ModifierPoolEntry]:
	var pool_set := ModifierPoolSet.new()
	pool_set.packs = [_PACK.duplicate(true)]
	return pool_set.flatten_for_node(&"wisdom", subtype)

## The one xp_per_turn +% pool whose `subtypes` does NOT name `bless` — i.e.
## the small pre-#1093 pool, not the fat blessed replacement. Both share
## `stat_id`/`operation` (StatPool._update_resource_name overwrites
## resource_name identically for both, so that can't distinguish them either).
func _find_small_xp_pct_pool() -> StatPool:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	for sp in p.pools:
		var pp := sp as StatPool
		if pp.stat_id != &"xp_per_turn" or pp.operation != StatModifier.Operation.INCREASE:
			continue
		var names_bless := false
		for s in pp.subtypes:
			if s != null and s.id == &"bless":
				names_bless = true
		if not names_bless:
			return pp
	return null

## #1093 — blessed WIS is the XP engine plus recovery, replacing the small
## xp_per_turn +% pool (decision 11/18).
func test_blessed_wisdom_gets_the_fat_xp_pair_and_wound_heal() -> void:
	var bless := NodeSubtype.new(); bless.id = &"bless"
	var ids: Array[StringName] = []
	for e in _flatten(bless):
		if not e.stat_id in ids: ids.append(e.stat_id)
	assert_true(&"wound_heal_per_turn" in ids, "blessed WIS must roll wound_heal_per_turn")
	assert_true(&"xp_per_turn" in ids, "blessed WIS must roll xp_per_turn")
	var small_pool: StatPool = _find_small_xp_pct_pool()
	assert_not_null(small_pool, "the small xp_per_turn +% pool must still exist")
	assert_false(small_pool.admits_subtype(bless),
		"blessed WIS must NOT roll the small xp_per_turn +% pool (decision 11/18: replace, not add)")

func test_regular_wisdom_keeps_the_small_pool_not_the_fat_pair() -> void:
	var regular := NodeSubtype.regular()
	var ids: Array[StringName] = []
	for e in _flatten(regular):
		if not e.stat_id in ids: ids.append(e.stat_id)
	assert_false(&"wound_heal_per_turn" in ids, "regular WIS must not roll wound_heal_per_turn")
	assert_false(&"dot_stacks_per_hit" in ids, "regular WIS must not roll dot_stacks_per_hit")
	assert_true(&"xp_per_turn" in ids, "regular WIS keeps the small xp_per_turn +% pool")

## #1094 — blighted WIS is the archive umbrella, trading the XP trickle.
func test_blighted_wisdom_gets_the_archive_umbrella_not_the_xp_trickle() -> void:
	var blight := NodeSubtype.new(); blight.id = &"blight"
	var ids: Array[StringName] = []
	for e in _flatten(blight):
		if not e.stat_id in ids: ids.append(e.stat_id)
	assert_true(&"dot_stacks_per_hit" in ids, "blighted WIS must roll dot_stacks_per_hit")
	var small_pool: StatPool = _find_small_xp_pct_pool()
	assert_not_null(small_pool, "the small xp_per_turn +% pool must still exist")
	assert_false(small_pool.admits_subtype(blight),
		"blighted WIS must NOT roll the small xp_per_turn +% pool (the XP trickle give-up)")

func test_draw_only_emits_pack_stat_ids() -> void:
	var pool_set := ModifierPoolSet.new()
	pool_set.packs = [_PACK.duplicate(true)]
	var ids: Array = []
	for seed_value in range(1, 25):
		var mods: Array = _GP._roll_modifiers_v4(pool_set, [], &"wisdom", &"wisdom", [] as Array[StringName], Vector2.ZERO, 0, 8, _rng(seed_value))
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
