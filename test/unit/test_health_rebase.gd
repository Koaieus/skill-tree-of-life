extends GutTest

## The lv1 HP scale: one ~100 bar for cores and nodes, a floor that takes
## ~20 hits to empty it, melee killing a lv1 core in ~10 hits, ranged sitting
## at the floor, magic scaled with the pools and per-stack DoT values left
## where they were.
##
## Every number here is a fresh lv1 entity's START (innate attributes, no
## addons, no rolls) — level, rolls and statuses move them all run. So these
## assert relations and ranges between the shipped knobs, never a literal
## default, except where the relation IS the decision (innate CON 0, the
## untouched per-stack DoT values).

const BOARD := preload("res://entity/default_entity_board.tres")
const BLOCKER_SMALL := preload("res://entity/blocker/blocker_small_board.tres")
const BLOCKER_MEDIUM := preload("res://entity/blocker/blocker_medium_board.tres")
const BLOCKER_LARGE := preload("res://entity/blocker/blocker_large_board.tres")
const NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const BUNKER := preload("res://skill_node/addons/defs/bunker_addon.tscn")

const POISON := preload("res://effects/status/poison.tres")
const BLEEDING := preload("res://effects/status/bleeding.tres")
const CORRUPTION := preload("res://effects/status/corruption.tres")
const WITHER := preload("res://effects/status/wither.tres")


func _lv1(source: EntityStatBoard) -> EntityStatBoard:
	var b := source.duplicate(true) as EntityStatBoard
	b.apply_intrinsics()
	return b


func _num(b: StatBoard, id: StringName) -> float:
	return float(b.get_value(id))


# ── One scale ───────────────────────────────────────────────────────────────

func test_innate_constitution_is_zero_so_lv1_health_is_the_base() -> void:
	for src in [BOARD, BLOCKER_SMALL, BLOCKER_MEDIUM, BLOCKER_LARGE]:
		var b := _lv1(src)
		assert_eq(_num(b, &"constitution"), 0.0, "%s: innate CON" % src.resource_path)
		assert_eq(_num(b, &"health"), b.health.base_value,
			"%s: lv1 health max must read the bare board base" % src.resource_path)


func test_core_and_node_share_one_scale() -> void:
	var b := _lv1(BOARD)
	assert_eq(_num(b, &"health"), _num(b, &"node_health"),
		"lv1 core health and node health are the same bar")


func test_a_pure_floor_kill_takes_about_twenty_hits() -> void:
	var b := _lv1(BOARD)
	var hits := _num(b, &"health") / _num(b, &"min_damage_taken")
	assert_between(hits, 17.0, 25.0, "lv1 health / floor = %s" % hits)


# ── Damage relative to the floor and the pools ──────────────────────────────

func test_lv1_melee_kills_a_core_in_eight_to_twelve_hits_and_ranged_sits_above_the_floor() -> void:
	var b := _lv1(BOARD)
	var melee := _num(b, &"blade_damage")
	var ranged := _num(b, &"ranged_damage")
	var floor_v := _num(b, &"min_damage_taken")
	var hits := _num(b, &"health") / melee
	assert_between(hits, 8.0, 12.0, "lv1 melee hits to kill = %s" % hits)
	assert_gte(ranged, floor_v, "lv1 ranged raw %s vs floor %s" % [ranged, floor_v])
	assert_lt(ranged, melee, "lv1 ranged raw %s must stay below melee raw %s" % [ranged, melee])


func test_a_power_one_spell_is_five_to_ten_percent_of_a_lv1_core_and_doubles_by_int_100() -> void:
	var b := _lv1(BOARD)
	var share := _num(b, &"spell_damage") * 1.0 / _num(b, &"health")
	assert_between(share, 0.05, 0.10, "power-1 spell share of lv1 core = %s" % share)

	var at_zero := _lv1(BOARD)
	at_zero.intelligence.base_value = 0.0
	var at_hundred := _lv1(BOARD)
	at_hundred.intelligence.base_value = 100.0
	var ratio := _num(at_hundred, &"spell_damage") / _num(at_zero, &"spell_damage")
	assert_between(ratio, 1.8, 2.2, "spell_damage at INT 100 / INT 0 = %s" % ratio)


func test_every_board_carries_lootable_innate_base_damage() -> void:
	var loot := LootSystem.new()
	autofree(loot)
	for src in [BOARD, BLOCKER_SMALL, BLOCKER_MEDIUM, BLOCKER_LARGE]:
		for id in [&"blade_damage", &"ranged_damage", &"spell_damage"]:
			var innate: StatModifier = null
			for m in (src as EntityStatBoard).intrinsic_modifiers:
				if m.stat_id == id and m.operation == StatModifier.Operation.ADD_BASE \
						and m.formula == null:
					innate = m
					break
			assert_not_null(innate,
				"%s: no innate ADD_BASE for %s" % [src.resource_path, id])
			if innate == null:
				continue
			assert_false(innate.resource_name.is_empty(),
				"%s: %s innate needs a loot-picker name" % [src.resource_path, id])
			for fraction in loot.loot_fraction_by_tier:
				if fraction > 1.0:
					continue
				var scaled := innate.value * fraction
				assert_almost_eq(scaled, roundf(scaled), 0.0001,
					"%s: %s innate %s × tier fraction %s must stay whole"
						% [src.resource_path, id, innate.value, fraction])


func test_a_default_board_kill_offers_its_innate_blade_damage_at_the_tier_fraction() -> void:
	var loot := LootSystem.new()
	autofree(loot)
	var victim := autofree(Entity.new()) as Entity
	victim.stat_board = BOARD.duplicate(true) as EntityStatBoard
	victim.entity_tier = 1

	var innate: StatModifier = null
	for m in victim.stat_board.intrinsic_modifiers:
		if m.stat_id == &"blade_damage" and m.operation == StatModifier.Operation.ADD_BASE \
				and m.formula == null:
			innate = m
			break
	assert_not_null(innate, "fixture: the default board carries an innate blade-damage modifier")
	if innate == null:
		return

	var fraction: float = loot.loot_fraction_by_tier[victim.entity_tier - 1]
	var expected := innate.value * fraction
	var draw := loot._draw_payload(victim)
	var offered: StatModifier = null
	for m in draw["candidates"]:
		if m.stat_id == &"blade_damage" and m.operation == StatModifier.Operation.ADD_BASE \
				and m.formula == null:
			offered = m
			break
	assert_not_null(offered, "the kill payload offers the board's innate blade damage")
	if offered != null:
		assert_almost_eq(offered.value, expected, 0.0001,
			"offered innate scales to the victim's tier fraction %s" % fraction)


# ── Dormant Cores ───────────────────────────────────────────────────────────

func test_blocker_cores_are_one_two_three_and_small_is_a_default_core() -> void:
	var small := _num(_lv1(BLOCKER_SMALL), &"health")
	assert_eq(_num(_lv1(BLOCKER_MEDIUM), &"health"), 2.0 * small, "medium = 2 × small")
	assert_eq(_num(_lv1(BLOCKER_LARGE), &"health"), 3.0 * small, "large = 3 × small")
	assert_eq(small, _num(_lv1(BOARD), &"health"), "small == the default lv1 core")


func test_blocker_health_pool_starts_full() -> void:
	for src in [BLOCKER_SMALL, BLOCKER_MEDIUM, BLOCKER_LARGE]:
		var hp := (src as EntityStatBoard).health
		assert_eq(hp.current, hp.base_value, "%s spawns at full health" % src.resource_path)


# ── Per-stack DoT values do not move (the decision, not a tuning) ───────────

func test_per_stack_dot_values_are_unchanged() -> void:
	assert_eq(POISON.damage_per_power, 1.0, "poison per stack per tick")
	assert_eq(BLEEDING.bleed_rate, 0.5, "bleed per stack")
	assert_gt(CORRUPTION.damage_per_power, 0.0, "corruption fraction of max HP per stack (a knob, not pinned)")
	assert_eq(WITHER.factor_per_stack, 0.1, "wither healing factor per stack")


# ── Bunker nets the default floor to zero ───────────────────────────────────

func test_bunker_on_a_default_node_nets_the_floor_to_zero() -> void:
	var ent := autofree(Entity.new()) as Entity
	ent.stat_board = BOARD.duplicate(true) as EntityStatBoard
	var node: SkillNode = NODE_SCENE.instantiate()
	autofree(node)
	add_child(ent)
	add_child(node)
	node.owned_by = ent
	await get_tree().process_frame
	node.add_child(BUNKER.instantiate())
	await get_tree().process_frame
	assert_almost_eq(float(node.get_local_value(&"min_damage_taken")), 0.0, 0.001,
		"a lone Bunker nets the default floor to 0")
