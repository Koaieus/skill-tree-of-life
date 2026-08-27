extends GutTest

## #629 — uniform roll bounds/reachability + the fused-no-op re-roll.
## Entry-level (ModifierPoolEntry.roll / StatPool.to_entries) tests live here
## rather than test_stat_draw.gd because they're about a single tier's own
## contract, independent of the spend-until-broke pipeline. The pipeline-level
## determinism tests (same seed / different seed / zero-width RNG
## consumption) live in test_stat_draw.gd alongside the rest of the draw.

const _GP := preload("res://procgen/graph_procgen.gd")
const _MPE := preload("res://procgen/pools/modifier_pool_entry.gd")


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _entry(op: int, lo: float, hi: float, stat_id: StringName = &"strength") -> ModifierPoolEntry:
	var e := ModifierPoolEntry.new()
	e.stat_id = stat_id
	e.operation = op as StatModifier.Operation
	e.value_range = Vector2(lo, hi)
	e.cost = 1
	return e


func _mod(op: int, value: float, stat_id: StringName = &"strength") -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = op as StatModifier.Operation
	m.value = value
	return m


# ── Acceptance 3: bounds + reachability ────────────────────────────────────

func test_rolled_values_stay_within_bounds_and_reach_both_ends() -> void:
	var e := _entry(StatModifier.Operation.ADD_BASE, 1.0, 5.0)
	var lo_min := INF
	var hi_max := -INF
	for seed_value in range(1, 1000):
		var v: float = e.roll(_rng(seed_value)).value
		assert_true(v >= 1.0 and v <= 5.0, "roll %s out of [1,5]" % v)
		lo_min = minf(lo_min, v)
		hi_max = maxf(hi_max, v)
	assert_lt(lo_min, 1.4, "1000 samples should approach the low bound; got min %s" % lo_min)
	assert_gt(hi_max, 4.6, "1000 samples should approach the high bound; got max %s" % hi_max)


# ── Acceptance 4: non-overlap survives rolling (positive M) ────────────────

func test_non_overlap_survives_rolling_for_positive_m() -> void:
	var p := StatPool.new()
	p.stat_id = &"strength"
	p.operation = StatModifier.Operation.ADD_BASE
	p.unit_value = 5.0
	p.range_floor = 1.0  # positive M → structurally non-overlapping (#628)
	p.min_tier = 1
	p.max_tier = 4
	var entries := p.to_entries()
	var maxes: Array[float] = []
	var mins: Array[float] = []
	for e in entries:
		maxes.append(-INF)
		mins.append(INF)
	for seed_value in range(1, 300):
		var rng := _rng(seed_value)
		for i in entries.size():
			var v: float = entries[i].roll(rng).value
			maxes[i] = maxf(maxes[i], v)
			mins[i] = minf(mins[i], v)
	for i in range(entries.size() - 1):
		assert_lt(maxes[i], mins[i + 1], "T%d's highest sample must stay below T%d's lowest" % [i + 1, i + 2])


# ── Acceptance 5: value_overrides bypasses the roll entirely ───────────────

func test_value_override_pins_exact_value_every_roll() -> void:
	var p := StatPool.new()
	p.stat_id = &"strength"
	p.operation = StatModifier.Operation.ADD_BASE
	p.unit_value = 5.0
	p.min_tier = 2
	p.max_tier = 2
	p.value_overrides = {2: 42.0}
	var e := p.to_entries()[0]
	for seed_value in range(1, 50):
		assert_almost_eq(e.roll(_rng(seed_value)).value, 42.0, 0.0001, "override must pin exactly, every roll")


# ── Acceptance 7 + 8: neutral-element detection ────────────────────────────

func test_add_base_zero_is_neutral() -> void:
	assert_true(_GP._is_neutral_result(_mod(StatModifier.Operation.ADD_BASE, 0.0)))


func test_add_base_nonzero_is_not_neutral() -> void:
	assert_false(_GP._is_neutral_result(_mod(StatModifier.Operation.ADD_BASE, 3.0)))


func test_multiply_x1_is_neutral() -> void:
	assert_true(_GP._is_neutral_result(_mod(StatModifier.Operation.MULTIPLY, 1.0)))


func test_multiply_x0_is_not_neutral() -> void:
	# x0 annihilates — maximally impactful, never a no-op (issue's explicit call-out).
	assert_false(_GP._is_neutral_result(_mod(StatModifier.Operation.MULTIPLY, 0.0)))


func test_set_is_never_neutral() -> void:
	assert_false(_GP._is_neutral_result(_mod(StatModifier.Operation.SET, 0.0)))


# ── Acceptance 9: coercion-aware neutrality ─────────────────────────────────
# constitution is INT-typed (the StatDef default, unset) and crit_chance is
# FLOAT-typed (stats_system/defs/crit_chance.tres explicitly sets it) in the
# default StatRegistry — reused here as stand-ins rather than a
# purpose-built fixture stat.

func test_small_add_is_neutral_on_int_stat_but_not_float_stat() -> void:
	var int_def: StatDef = StatRegistry.get_def(&"constitution")
	var float_def: StatDef = StatRegistry.get_def(&"crit_chance")
	assert_eq(int_def.value_type, StatDef.ValueType.INT, "fixture assumption: constitution is INT")
	assert_eq(float_def.value_type, StatDef.ValueType.FLOAT, "fixture assumption: crit_chance is FLOAT")
	assert_true(_GP._is_neutral_result(_mod(StatModifier.Operation.ADD_BASE, 0.4, &"constitution")),
			"+0.4 on an INT stat rounds to 0 — a no-op")
	assert_false(_GP._is_neutral_result(_mod(StatModifier.Operation.ADD_BASE, 0.4, &"crit_chance")),
			"+0.4 on a FLOAT stat stays 0.4 — not a no-op")


# ── Acceptance 7/10/11: the re-roll pass, through the real draw pipeline ───

## Rigged to force at least one re-roll: a single MULTIPLY pool with
## unit_value 0.0 always fuses to the neutral ×1 (mag is always 0, so every
## roll mints ×(1+0)=×1). Every draw must retry up to the cap and then be
## dropped — deterministically.
func _neutral_multiply_pool_set() -> ModifierPoolSet:
	var p := StatPool.new()
	p.stat_id = &"strength"
	p.operation = StatModifier.Operation.MULTIPLY
	p.archetype_stat = &"strength"
	p.unit_value = 0.0
	p.pool_weight = 1.0
	p.min_tier = 1
	p.max_tier = 1
	var pack := StatPack.new()
	pack.archetype_stat = &"strength"
	var pools: Array[StatPool] = [p]
	pack.pools = pools
	var set := ModifierPoolSet.new()
	var packs: Array[StatPack] = [pack]
	set.packs = packs
	return set


func test_always_neutral_pool_is_dropped_after_retry_cap() -> void:
	var pool_set := _neutral_multiply_pool_set()
	var fp := {}
	var mods: Array = _GP._roll_modifiers_v4(pool_set, [], &"strength", &"strength", [] as Array[StringName], Vector2.ZERO, 0, 4, _rng(11), fp)
	assert_eq(mods.size(), 0, "a permanently-neutral fused result must be dropped, not emitted")
	assert_gt(fp.get("no_op_retries", 0), 0, "the retry path should have fired")
	assert_gt(fp.get("dropped", 0), 0, "the drop path should have fired")


func test_no_op_retry_is_deterministic_across_identical_seeds() -> void:
	var pool_set := _neutral_multiply_pool_set()
	var fp_a := {}
	var fp_b := {}
	var mods_a: Array = _GP._roll_modifiers_v4(pool_set, [], &"strength", &"strength", [] as Array[StringName], Vector2.ZERO, 0, 4, _rng(11), fp_a)
	var mods_b: Array = _GP._roll_modifiers_v4(pool_set, [], &"strength", &"strength", [] as Array[StringName], Vector2.ZERO, 0, 4, _rng(11), fp_b)
	assert_eq(mods_a.size(), mods_b.size())
	assert_eq(fp_a.get("no_op_retries"), fp_b.get("no_op_retries"), "same seed must retry the same number of times")
	assert_eq(fp_a.get("dropped"), fp_b.get("dropped"))


## A pool that starts negative-EV (range_floor = -unit_value*2) but has real
## width can still fuse to a genuine non-neutral value on retry — proves the
## retry path recovers a usable modifier rather than always exhausting the cap.
func test_no_op_retry_can_recover_a_nonzero_result() -> void:
	var p := StatPool.new()
	p.stat_id = &"strength"
	p.operation = StatModifier.Operation.ADD_BASE
	p.archetype_stat = &"strength"
	p.unit_value = 5.0
	p.range_floor = -5.0  # T1 range -5..5, mean 0 — can fuse to exactly 0
	p.min_tier = 1
	p.max_tier = 1
	var pack := StatPack.new()
	pack.archetype_stat = &"strength"
	var pools: Array[StatPool] = [p]
	pack.pools = pools
	var set := ModifierPoolSet.new()
	var packs: Array[StatPack] = [pack]
	set.packs = packs
	var saw_nonzero := false
	for seed_value in range(1, 100):
		var mods: Array = _GP._roll_modifiers_v4(set, [], &"strength", &"strength", [] as Array[StringName], Vector2.ZERO, 0, 1, _rng(seed_value))
		if mods.size() > 0:
			saw_nonzero = true
			assert_ne(mods[0].value, 0.0, "an emitted result must not be the neutral element")
	assert_true(saw_nonzero, "at least one seed should recover a non-neutral result across 99 tries")
