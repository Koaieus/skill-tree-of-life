extends GutTest
## v4 StatPool conformance for perception.tres (#321 wave 1).
const _PACK := preload("res://procgen/pools/perception.tres")
const _GP := preload("res://procgen/graph_procgen.gd")

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func test_pack_loads_as_statpack() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	assert_not_null(p)
	assert_eq(p.archetype_stat, &"perception")
	assert_true(p.pools.size() > 0)


func test_perception_pool_values() -> void:
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
		if pp.stat_id == &"perception" and pp.operation == StatModifier.Operation.ADD_BASE:
			found = true
			assert_eq(pp.to_entries(p.archetype_stat).size(), pp.max_tier - pp.min_tier + 1,
					"perception.addb: one entry per offered tier")
	assert_true(found, "the pack must carry a perception addb pool at all")


func _flatten(subtype: NodeSubtype) -> Array[ModifierPoolEntry]:
	var pool_set := ModifierPoolSet.new()
	pool_set.packs = [_PACK.duplicate(true)]
	return pool_set.flatten_for_node(&"perception", subtype)

## #1095 — blighted PER blinds (trades sensor_range), blessed PER resists
## blinding (trades the flat vision_range +), scout arrows stay shared.
func test_blighted_perception_gets_blindness_potency_not_sensor_range() -> void:
	var blight := NodeSubtype.new(); blight.id = &"blight"
	var ids: Array[StringName] = []
	for e in _flatten(blight):
		if not e.stat_id in ids: ids.append(e.stat_id)
	assert_true(&"blindness_potency" in ids, "blighted PER must roll blindness_potency")
	assert_false(&"sensor_range" in ids, "blighted PER must NOT roll sensor_range (trades it away)")
	assert_true(&"scout_arrows_per_reload" in ids, "scout arrows stay shared by all three poles")

func test_blessed_perception_gets_blindness_resistance_not_flat_vision() -> void:
	var bless := NodeSubtype.new(); bless.id = &"bless"
	var ids: Array[StringName] = []
	var flat_vision := false
	for e in _flatten(bless):
		if not e.stat_id in ids: ids.append(e.stat_id)
		if e.stat_id == &"vision_range" and e.operation == StatModifier.Operation.ADD_BONUS:
			flat_vision = true
	assert_true(&"blindness_resistance" in ids, "blessed PER must roll blindness_resistance")
	assert_false(flat_vision, "blessed PER must NOT roll the flat vision_range + pool (trades it away)")
	assert_true(&"vision_range" in ids, "blessed PER keeps vision_range +%")
	assert_true(&"scout_arrows_per_reload" in ids, "scout arrows stay shared by all three poles")

func test_regular_perception_keeps_both_existing_pools_neither_new_one() -> void:
	var regular := NodeSubtype.regular()
	var ids: Array[StringName] = []
	var flat_vision := false
	for e in _flatten(regular):
		if not e.stat_id in ids: ids.append(e.stat_id)
		if e.stat_id == &"vision_range" and e.operation == StatModifier.Operation.ADD_BONUS:
			flat_vision = true
	assert_true(&"sensor_range" in ids, "regular PER keeps sensor_range")
	assert_true(flat_vision, "regular PER keeps the flat vision_range + pool")
	assert_false(&"blindness_potency" in ids, "regular PER must not roll blindness_potency")
	assert_false(&"blindness_resistance" in ids, "regular PER must not roll blindness_resistance")

func test_perception_draw_only_emits_pack_stat_ids() -> void:
	var pool_set := ModifierPoolSet.new()
	pool_set.packs = [_PACK.duplicate(true)]
	var primary := &"perception"
	var ids: Array = []
	for seed_value in range(1, 25):
		var mods: Array = _GP._roll_modifiers_v4(pool_set, [], primary, primary, [] as Array[StringName], Vector2.ZERO, 0, 8, _rng(seed_value))
		for m in mods:
			if not (m.stat_id in ids):
				ids.append(m.stat_id)
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
