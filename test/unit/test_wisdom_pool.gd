extends GutTest

## Regression for #272 (D-17): procgen/pools/wisdom.tres was rescaled for
## xp_per_turn = WIS // 2 (#271, not yet landed). These bounds are a lint
## against the pool drifting back toward its pre-rescale magnitudes, and
## against the `.tres` silent-strip / UID-mismatch failure documented in
## `.claude/rules/godot-workflow.md` (symptom is a null field, not a parse
## error).
##
## Pinned ceilings (D-17 decisions 3 & 4): INCREASE tiers ~10% max,
## MULTIPLY tiers 1.05-1.10 except the single mythic-tagged ×1.5 draw.
## The additive ceiling below (_ADD_CEILING) is NOT pinned — it is this
## pool's # TBD (#268) proposal for the 100-200 mid-game band and awaits
## human confirmation.

const _WISDOM := preload("res://procgen/pools/wisdom.tres")

const _ADD_CEILING := 50.0     # TBD (#268) — proposed additive tier ceiling
const _INCREASE_CEILING := 10.0 # pinned: D-17 decision 3 ("~10% for the most expensive roll")
const _MULTIPLY_CEILING := 1.10 # pinned: D-17 decision 4, except the mythic tier


func test_wisdom_pack_loads() -> void:
	var pack: StatPack = _WISDOM.duplicate(true) as StatPack
	assert_not_null(pack, "wisdom.tres should load as a StatPack")
	assert_eq(pack.archetype_stat, &"wisdom")


func test_every_subpool_is_non_null_with_nonempty_tiers() -> void:
	# Lint against silent .tres strip / UID mismatch: a broken ext_resource
	# resolves the SubResource as a bare Resource with no script, and any
	# field referencing it reads null instead of erroring.
	var pack: StatPack = _WISDOM.duplicate(true) as StatPack
	assert_true(pack.pools.size() > 0, "expected at least one TierPool on the wisdom pack")
	for pool in pack.pools:
		assert_not_null(pool, "a wisdom sub-pool resolved to null — check ext_resource uids")
		var tier_pool: TierPool = pool as TierPool
		assert_not_null(tier_pool, "sub-pool did not resolve to a TierPool — script attachment lost")
		assert_true(tier_pool.tiers.size() > 0, "sub-pool %s has an empty tiers array" % String(tier_pool.stat_id))
		for t in tier_pool.tiers:
			assert_not_null(t, "a tier in sub-pool %s resolved to null" % String(tier_pool.stat_id))


func test_additive_tiers_stay_under_ceiling() -> void:
	# Scoped to the `wisdom` stat pools specifically — those are what D-17
	# rescales (WIS itself feeds xp_per_turn = WIS // 2 under #271). The
	# `xp_per_turn` sub-pools target that stat directly and were already
	# tuned for it independent of the divisor; decision 5 asks only that
	# their *weight* recede, not their magnitude.
	var pack: StatPack = _WISDOM.duplicate(true) as StatPack
	var checked_any := false
	for pool in pack.pools:
		var tier_pool: TierPool = pool as TierPool
		if tier_pool.operation != StatModifier.Operation.ADD_BASE or tier_pool.stat_id != &"wisdom":
			continue
		for t in tier_pool.tiers:
			var td: TierDef = t as TierDef
			checked_any = true
			assert_true(td.value_range.y <= _ADD_CEILING,
					"ADD_BASE tier on %s rolls up to %.1f, exceeds proposed ceiling %.1f" % [
							String(tier_pool.stat_id), td.value_range.y, _ADD_CEILING])
	assert_true(checked_any, "expected at least one ADD_BASE tier to check")


func test_increase_tiers_stay_under_pinned_ceiling() -> void:
	# Scoped to `wisdom` for the same reason as the additive test above.
	var pack: StatPack = _WISDOM.duplicate(true) as StatPack
	var checked_any := false
	for pool in pack.pools:
		var tier_pool: TierPool = pool as TierPool
		if tier_pool.operation != StatModifier.Operation.INCREASE or tier_pool.stat_id != &"wisdom":
			continue
		for t in tier_pool.tiers:
			var td: TierDef = t as TierDef
			checked_any = true
			assert_true(td.value_range.y <= _INCREASE_CEILING,
					"INCREASE tier on %s rolls up to %.1f%%, exceeds pinned ~%.0f%% ceiling" % [
							String(tier_pool.stat_id), td.value_range.y, _INCREASE_CEILING])
	assert_true(checked_any, "expected at least one INCREASE tier to check")


func test_multiply_tiers_stay_under_pinned_ceiling_except_mythic() -> void:
	var pack: StatPack = _WISDOM.duplicate(true) as StatPack
	var checked_any := false
	var saw_mythic := false
	for pool in pack.pools:
		var tier_pool: TierPool = pool as TierPool
		if tier_pool.operation != StatModifier.Operation.MULTIPLY:
			continue
		for t in tier_pool.tiers:
			var td: TierDef = t as TierDef
			checked_any = true
			var is_mythic := &"mythic" in td.extra_tags
			if is_mythic:
				saw_mythic = true
				assert_true(td.value_range.y <= 1.5 + 0.001,
						"mythic MULTIPLY tier on %s rolls up to x%.2f, expected the x1.5 mythic ceiling" % [
								String(tier_pool.stat_id), td.value_range.y])
			else:
				# +0.001 epsilon: TierDef.value_range is a Vector2 (float32);
				# authoring exactly 1.10 can round up a hair past the double
				# ceiling constant on comparison.
				assert_true(td.value_range.y <= _MULTIPLY_CEILING + 0.001,
						"non-mythic MULTIPLY tier on %s rolls up to x%.2f, exceeds pinned x%.2f ceiling" % [
								String(tier_pool.stat_id), td.value_range.y, _MULTIPLY_CEILING])
	assert_true(checked_any, "expected at least one MULTIPLY tier to check")
	assert_true(saw_mythic, "expected exactly one mythic-tagged MULTIPLY tier reserved for the x1.5 tail")


func test_all_three_operations_still_represented() -> void:
	# Regression guard on D-17 decision 1: WIS keeps ADD_BASE, INCREASE and
	# MULTIPLY — no sub-pool may be deleted.
	var pack: StatPack = _WISDOM.duplicate(true) as StatPack
	var seen_ops: Dictionary = {}
	for pool in pack.pools:
		var tier_pool: TierPool = pool as TierPool
		seen_ops[tier_pool.operation] = true
	assert_true(seen_ops.has(StatModifier.Operation.ADD_BASE), "ADD_BASE sub-pool missing")
	assert_true(seen_ops.has(StatModifier.Operation.INCREASE), "INCREASE sub-pool missing")
	assert_true(seen_ops.has(StatModifier.Operation.MULTIPLY), "MULTIPLY sub-pool missing")
