extends GutTest

## The per-cast half of an infusion (#1250): points spent on a cast fold into
## the spell's affinity at its ingest rate (floored), and a [MagicAttackPlan]
## reports how far the spend runs past the caster's caps — per-aspect stat,
## `infusion_slots` (breadth), `infusion_points` / `SpellDef.infusion_capacity`
## (depth) and the spell's refusals.

const _CYCLONE: SpellDef = preload("res://attack/spell/defs/cyclone.tres")
const _VENOM: SpellDef = preload("res://attack/spell/defs/venom.tres")
const _SPARK: SpellDef = preload("res://attack/spell/defs/spark.tres")

var h: SpellTestHelper


func before_each() -> void:
	h = SpellTestHelper.new()


func _infused(spell: SpellDef, points: Dictionary) -> Infusion:
	return Infusion.for_cast(spell, points)


func _rider_power(inf: Infusion, spell: SpellDef, id: StringName) -> float:
	for rider in inf.riders(spell):
		var apply := rider as ApplyStatusEffect
		if apply != null and apply.def != null and apply.def.identity != null \
				and apply.def.identity.id == id:
			return apply.power
	return 0.0


# ── the ingest arithmetic ───────────────────────────────────────────────

func test_cyclone_ingests_at_half_rate_and_floors() -> void:
	var one := _infused(_CYCLONE, {&"poison": 1})
	assert_eq(one.affinity_of(_CYCLONE).get(&"poison", 0), 0, "1 point at 1:2 floors to nothing")
	assert_eq(_rider_power(one, _CYCLONE, &"poison"), 0.0, "and lands no poison rider")
	var four := _infused(_CYCLONE, {&"poison": 4})
	assert_eq(four.affinity_of(_CYCLONE).get(&"poison", 0), 2, "4 points at 1:2 is 2")
	assert_eq(_rider_power(four, _CYCLONE, &"poison"), 2.0, "2 poison per landing")


func test_venom_ingests_at_double_rate_on_top_of_innate() -> void:
	var inf := _infused(_VENOM, {&"poison": 3})
	assert_eq(inf.affinity_of(_VENOM).get(&"poison", 0), 11, "innate 5 + floor(3 x 2)")
	assert_eq(_rider_power(inf, _VENOM, &"poison"), 11.0)


func test_innate_infusion_spends_nothing() -> void:
	var inf := Infusion.innate(_VENOM)
	assert_true(inf.points.is_empty())
	assert_eq(inf.slots_used(), 0)
	assert_eq(inf.affinity_of(_VENOM).get(&"poison", 0), 5)


func test_slots_used_counts_aspects_with_points() -> void:
	var inf := _infused(_SPARK, {&"poison": 2, &"curse": 0, &"wither": 1})
	assert_eq(inf.slots_used(), 2)


# ── the plan's overrun ──────────────────────────────────────────────────

func _plan(spell: SpellDef, intelligence: float) -> MagicAttackPlan:
	var graph := h.make_graph([[0, 1]], self)
	var atk := h.make_entity(graph, "ATK", Color.RED)
	atk.stat_board.intelligence.base_value = intelligence
	atk.stat_board.poison_aspect.base_value = 20.0
	atk.stat_board.curse_aspect.base_value = 20.0
	var plan := MagicAttackPlan.new()
	plan.attacker = atk
	plan.set_spell(spell)
	return plan


func test_infusion_stats_derive_from_int() -> void:
	var plan := _plan(_SPARK, 100.0)
	var board := plan.attacker.stat_board
	assert_eq(int(board.get_value(&"infusion_slots")), 1, "first slot at 100 INT")
	assert_eq(int(board.get_value(&"infusion_points")), 10, "floor(sqrt(100))")
	board.intelligence.base_value = 1000.0
	assert_eq(int(board.get_value(&"infusion_slots")), 2, "second slot at 1000 INT")
	assert_eq(int(board.get_value(&"infusion_points")), 31, "floor(sqrt(1000))")


func test_a_fresh_plan_is_innate_only_and_within_caps() -> void:
	var plan := _plan(_SPARK, 0.0)
	assert_not_null(plan.infusion)
	assert_true(plan.infusion.points.is_empty())
	assert_eq(plan.aspect_overrun(), 0)


func test_two_aspects_on_one_slot_overrun_by_one() -> void:
	var plan := _plan(_SPARK, 100.0)
	plan.set_infusion(&"poison", 1)
	plan.set_infusion(&"curse", 1)
	assert_eq(plan.aspect_overrun(), 1, "2 aspects on infusion_slots 1")


func test_points_above_the_aspect_stat_count() -> void:
	var plan := _plan(_SPARK, 100.0)
	plan.attacker.stat_board.poison_aspect.base_value = 2.0
	plan.set_infusion(&"poison", 5)
	assert_eq(plan.aspect_overrun(), 3, "5 poison on poison_aspect 2")


func test_points_above_the_pool_count() -> void:
	var plan := _plan(_SPARK, 100.0)
	plan.set_infusion(&"poison", 12)
	assert_eq(plan.aspect_overrun(), 2, "12 points on infusion_points 10")


func test_spell_capacity_caps_below_the_pool() -> void:
	var spell := _SPARK.duplicate() as SpellDef
	spell.infusion_capacity = 4.0
	var plan := _plan(spell, 10000.0)
	plan.set_infusion(&"poison", 6)
	assert_eq(plan.aspect_overrun(), 2, "6 points on a capacity-4 spell, pool 100")


func test_points_on_a_refused_aspect_count() -> void:
	var spell := _SPARK.duplicate() as SpellDef
	spell.default_rate = 0.0
	var plan := _plan(spell, 100.0)
	plan.set_infusion(&"poison", 3)
	assert_eq(plan.aspect_overrun(), 3, "a 0-rate aspect takes no points")


func test_set_infusion_emits_state_changed() -> void:
	var plan := _plan(_SPARK, 100.0)
	watch_signals(plan)
	plan.set_infusion(&"poison", 2)
	assert_signal_emitted(plan, "state_changed")
	assert_eq(plan.infusion.points.get(&"poison", 0), 2)


func test_set_spell_resets_the_infusion() -> void:
	var plan := _plan(_SPARK, 100.0)
	plan.set_infusion(&"poison", 2)
	plan.set_spell(_VENOM)
	assert_true(plan.infusion.points.is_empty())


# ── the wire ────────────────────────────────────────────────────────────

func test_wire_round_trips_points() -> void:
	var plan := _plan(_SPARK, 100.0)
	plan.set_infusion(&"poison", 3)
	plan.set_infusion(&"curse", 1)
	var graph := plan.attacker.get_parent() as Graph
	var back := MagicAttackPlan.from_dict(plan.to_dict(graph), graph)
	assert_eq(back.infusion.points.get(&"poison", 0), 3)
	assert_eq(back.infusion.points.get(&"curse", 0), 1)


func test_an_uninfused_plan_ships_no_infusion_key() -> void:
	var plan := _plan(_SPARK, 100.0)
	var graph := plan.attacker.get_parent() as Graph
	assert_false(plan.to_dict(graph).has("infusion"))
	var back := MagicAttackPlan.from_dict(plan.to_dict(graph), graph)
	assert_not_null(back.infusion)
	assert_true(back.infusion.points.is_empty())
