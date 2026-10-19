extends GutTest
## Roll passes: a subtype names extra passes, a pool lists the passes that draw
## it (`[]` = budget only). An extra pass spends no budget and makes one
## weighted pick. See docs/domain/node-subtypes.md § Roll passes.

const _SET := preload("res://procgen/pools/specimen_pool_set.tres")
const _BLIGHT := preload("res://procgen/subtypes/blight.tres")

const _BUDGET_STAT := &"dexterity"
const _SUPPLY_STAT := &"poison_aspect"


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _subtype(id_: StringName, passes: Array[RollPass] = []) -> NodeSubtype:
	var s := NodeSubtype.new()
	s.id = id_
	s.extra_passes = passes
	return s


func _roll_pass(id_: StringName, chance: float) -> RollPass:
	var p := RollPass.new()
	p.id = id_
	p.chance = chance
	return p


func _pool(stat: StringName, passes: Array[StringName], subs: Array[NodeSubtype] = []) -> StatPool:
	var p := StatPool.new()
	p.stat_id = stat
	p.passes = passes
	p.subtypes = subs
	return p


func _set_of(pools: Array[StatPool]) -> ModifierPoolSet:
	var pack := StatPack.new()
	pack.archetype_stat = &"dexterity"
	pack.pools = pools
	var packs: Array[StatPack] = [pack]
	var s := ModifierPoolSet.new()
	s.packs = packs
	return s


func _stats(entries: Array[ModifierPoolEntry]) -> Dictionary:
	var out := {}
	for e in entries:
		out[e.stat_id] = true
	return out


func _roll(pool_set: ModifierPoolSet, subtype: NodeSubtype, seed_value: int, budget: int = 1, fp: Dictionary = {}) -> Array[StatModifier]:
	return GraphProcgen._roll_modifiers_v4(pool_set, [], &"dexterity", &"dexterity",
		[] as Array[StringName], Vector2.ZERO, 0, budget, _rng(seed_value), fp, subtype)


func _mod_stats(mods: Array[StatModifier]) -> Dictionary:
	var out := {}
	for m in mods:
		out[m.stat_id] = true
	return out


# ── 1. the pass gate ─────────────────────────────────────────────────────

func test_empty_passes_is_budget_only() -> void:
	var pool_set := _set_of([_pool(_BUDGET_STAT, [] as Array[StringName])] as Array[StatPool])
	var regular := NodeSubtype.regular()
	assert_true(_stats(pool_set.flatten_for_node(&"dexterity", regular)).has(_BUDGET_STAT),
		"an empty `passes` pool is drawn in the budget pass")
	assert_true(pool_set.flatten_for_node(&"dexterity", regular, &"supply").is_empty(),
		"an empty `passes` pool is never drawn in an extra pass")


func test_supply_only_pool_is_never_in_the_budget_loop() -> void:
	var pool_set := _set_of([_pool(_SUPPLY_STAT, [&"supply"] as Array[StringName])] as Array[StatPool])
	var regular := NodeSubtype.regular()
	assert_true(pool_set.flatten_for_node(&"dexterity", regular).is_empty(),
		"a [supply]-only pool is not drawn by the budget loop")
	assert_true(pool_set.flatten_for_node(&"dexterity", regular, StatPool.BUDGET_PASS).is_empty())
	assert_true(_stats(pool_set.flatten_for_node(&"dexterity", regular, &"supply")).has(_SUPPLY_STAT))


func test_budget_and_supply_pool_is_drawn_in_both() -> void:
	var pool_set := _set_of([_pool(_SUPPLY_STAT, [&"budget", &"supply"] as Array[StringName])] as Array[StatPool])
	var regular := NodeSubtype.regular()
	assert_true(_stats(pool_set.flatten_for_node(&"dexterity", regular)).has(_SUPPLY_STAT))
	assert_true(_stats(pool_set.flatten_for_node(&"dexterity", regular, &"supply")).has(_SUPPLY_STAT))


# ── 2. the extra pass adds a stat and spends nothing ─────────────────────

func test_extra_pass_adds_a_stat_on_top_of_the_budget_pick() -> void:
	var pool_set := _set_of([
		_pool(_BUDGET_STAT, [] as Array[StringName]),
		_pool(_SUPPLY_STAT, [&"supply"] as Array[StringName]),
	] as Array[StatPool])
	var with_pass := _subtype(&"blight", [_roll_pass(&"supply", 1.0)] as Array[RollPass])
	var without := _subtype(&"blight")
	var fp_with := {}
	var fp_without := {}
	var mods := _mod_stats(_roll(pool_set, with_pass, 7, 1, fp_with))
	var base := _mod_stats(_roll(pool_set, without, 7, 1, fp_without))
	assert_true(mods.has(_BUDGET_STAT), "the budget pick still lands — got %s" % str(mods.keys()))
	assert_true(mods.has(_SUPPLY_STAT), "the supply pass adds its stat — got %s" % str(mods.keys()))
	assert_false(base.has(_SUPPLY_STAT), "no pass, no supply stat")
	assert_eq(fp_with.get("remaining"), fp_without.get("remaining"), "the extra pass spends no budget")
	assert_eq(fp_with.get("draws"), fp_without.get("draws"), "the extra pass is not a budget draw")


# ── 3. chance ────────────────────────────────────────────────────────────

func test_chance_zero_rolls_nothing_extra() -> void:
	var pool_set := _set_of([
		_pool(_BUDGET_STAT, [] as Array[StringName]),
		_pool(_SUPPLY_STAT, [&"supply"] as Array[StringName]),
	] as Array[StatPool])
	var sub := _subtype(&"blight", [_roll_pass(&"supply", 0.0)] as Array[RollPass])
	for s in 50:
		assert_false(_mod_stats(_roll(pool_set, sub, s)).has(_SUPPLY_STAT), "chance 0 never fires (seed %d)" % s)


func test_chance_half_fires_on_about_half_the_nodes() -> void:
	var pool_set := _set_of([
		_pool(_BUDGET_STAT, [] as Array[StringName]),
		_pool(_SUPPLY_STAT, [&"supply"] as Array[StringName]),
	] as Array[StatPool])
	var sub := _subtype(&"blight", [_roll_pass(&"supply", 0.5)] as Array[RollPass])
	var n := 400
	var hits := 0
	for s in n:
		if _mod_stats(_roll(pool_set, sub, s)).has(_SUPPLY_STAT):
			hits += 1
	var ratio := float(hits) / n
	assert_between(ratio, 0.35, 0.65, "chance 0.5 should fire on ~half the nodes — got %.3f" % ratio)


# ── 4. the subtype gate holds inside the pass ────────────────────────────

func test_subtype_gate_applies_inside_an_extra_pass() -> void:
	var bless := _subtype(&"bless")
	var pool_set := _set_of([
		_pool(_BUDGET_STAT, [] as Array[StringName]),
		_pool(_SUPPLY_STAT, [&"supply"] as Array[StringName], [bless] as Array[NodeSubtype]),
	] as Array[StatPool])
	var blight := _subtype(&"blight", [_roll_pass(&"supply", 1.0)] as Array[RollPass])
	for s in 50:
		assert_false(_mod_stats(_roll(pool_set, blight, s)).has(_SUPPLY_STAT),
			"a [bless]-gated supply pool is never drawn on a blighted node (seed %d)" % s)


# ── 5. determinism ───────────────────────────────────────────────────────

func test_same_seed_rolls_the_same_modifiers() -> void:
	var pool_set := _set_of([
		_pool(_BUDGET_STAT, [] as Array[StringName]),
		_pool(_SUPPLY_STAT, [&"supply"] as Array[StringName]),
		_pool(&"explosive_aspect", [&"budget", &"supply"] as Array[StringName]),
	] as Array[StatPool])
	var sub := _subtype(&"blight", [_roll_pass(&"supply", 0.5), _roll_pass(&"supply", 0.5)] as Array[RollPass])
	for s in 20:
		var a := _roll(pool_set, sub, s, 4)
		var b := _roll(pool_set, sub, s, 4)
		assert_eq(a.size(), b.size())
		for i in mini(a.size(), b.size()):
			assert_eq(a[i].stat_id, b[i].stat_id)
			assert_eq(a[i].operation, b[i].operation)
			assert_eq(a[i].value, b[i].value)


# ── 6. shipped data ──────────────────────────────────────────────────────

func test_blight_ships_a_supply_pass() -> void:
	var ids: Array[StringName] = []
	for p in _BLIGHT.extra_passes:
		ids.append(p.id)
	assert_has(ids, &"supply", "blighted nodes run the supply pass")


func test_shipped_supply_pass_reaches_exactly_each_schools_aspects() -> void:
	var checked := 0
	for pack in _SET.packs:
		if pack == null or pack.archetype_stat == &"":
			continue
		var aspects := {}
		for pool in pack.pools:
			if pool != null and String(pool.stat_id).ends_with("_aspect"):
				aspects[pool.stat_id] = true
		if aspects.is_empty():
			continue
		checked += 1
		var supply := _stats(_SET.flatten_for_node(pack.archetype_stat, _BLIGHT, &"supply"))
		for a in aspects:
			assert_true(supply.has(a), "%s: blight's supply pass must reach %s" % [pack.archetype_stat, a])
		for s in supply:
			assert_true(aspects.has(s), "%s: supply pass draws non-supply stat %s" % [pack.archetype_stat, s])
		var budget := _stats(_SET.flatten_for_node(pack.archetype_stat, _BLIGHT))
		for a in aspects:
			assert_true(budget.has(a), "%s: %s stays in the budget draw too" % [pack.archetype_stat, a])
	assert_eq(checked, 6, "every school pack carries supply entries")
