extends GutTest

## The per-cast half of an infusion (#1250): points spent on a cast fold into
## the spell's affinity at its ingest rate (floored), and a [MagicAttackPlan]
## reports how far the spend runs past the caster's caps — per-aspect stat,
## `infusion_slots` (breadth), `SpellDef.infusion_capacity` (the total) and the
## spell's refusals. No shared points pool (#1574): depth is the aspect held.

const _CYCLONE: SpellDef = preload("res://attack/spell/defs/cyclone.tres")
const _VENOM: SpellDef = preload("res://attack/spell/defs/venom_burst.tres")
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
	var aff: SpellAffinity = _VENOM.affinities[0]
	var expected := aff.innate + int(floor(3 * aff.rate))
	assert_eq(aff.rate, 2.0, "fixture: the dose ingests poison at 2:1")
	assert_eq(inf.affinity_of(_VENOM).get(&"poison", 0), expected, "innate + floor(3 x 2)")
	assert_eq(_rider_power(inf, _VENOM, &"poison"), float(expected))


func test_innate_infusion_spends_nothing() -> void:
	var inf := Infusion.innate(_VENOM)
	assert_true(inf.points.is_empty())
	assert_eq(inf.slots_used(), 0)
	assert_eq(inf.affinity_of(_VENOM).get(&"poison", 0), _VENOM.affinities[0].innate)


func test_slots_used_counts_aspects_with_points() -> void:
	var inf := _infused(_SPARK, {&"poison": 2, &"curse": 0, &"wither": 1})
	assert_eq(inf.slots_used(), 2)


# ── the plan's overrun ──────────────────────────────────────────────────

func _plan(spell: SpellDef, intelligence: float) -> MagicAttackPlan:
	var graph := h.make_graph([[0, 1]], self)
	var atk := h.make_entity(graph, "ATK", Color.RED)
	atk.stat_board.intelligence.base_value = intelligence
	atk.stat_board.facet(&"poison", StatDef.Role.ASPECT).base_value = 20.0
	atk.stat_board.facet(&"curse", StatDef.Role.ASPECT).base_value = 20.0
	var plan := MagicAttackPlan.new()
	plan.attacker = atk
	plan.set_spell(spell)
	return plan


func test_infusion_stats_derive_from_int() -> void:
	var plan := _plan(_SPARK, 10.0)
	var board := plan.attacker.stat_board
	assert_eq(int(board.get_value(&"infusion_slots")), 1, "first slot at 10 INT")
	board.intelligence.base_value = 100.0
	assert_eq(int(board.get_value(&"infusion_slots")), 2, "second slot at 100 INT")


func test_a_fresh_plan_is_innate_only_and_within_caps() -> void:
	var plan := _plan(_SPARK, 0.0)
	assert_not_null(plan.infusion)
	assert_true(plan.infusion.points.is_empty())
	assert_eq(plan.aspect_overrun(), 0)


func test_two_aspects_on_one_slot_overrun_by_one() -> void:
	var plan := _plan(_SPARK, 10.0)
	plan.set_infusion(&"poison", 1)
	plan.set_infusion(&"curse", 1)
	assert_eq(plan.aspect_overrun(), 1, "2 aspects on infusion_slots 1")


func test_points_above_the_aspect_stat_count() -> void:
	var plan := _plan(_SPARK, 10.0)
	plan.attacker.stat_board.facet(&"poison", StatDef.Role.ASPECT).base_value = 2.0
	plan.set_infusion(&"poison", 5)
	assert_eq(plan.aspect_overrun(), 3, "5 poison on poison_aspect 2")


func test_each_aspect_carries_what_it_holds_with_no_pool() -> void:
	var plan := _plan(_VENOM, 100.0)
	plan.attacker.stat_board.facet(&"poison", StatDef.Role.ASPECT).base_value = 40.0
	plan.set_infusion(&"poison", 40)
	plan.set_infusion(&"curse", 20)
	assert_eq(plan.aspect_overrun(), 0, "poison 40 + curse 20 at 2 slots, no total cap")


func test_spell_capacity_caps_the_total() -> void:
	var spell := _SPARK.duplicate() as SpellDef
	spell.infusion_capacity = 4.0
	var plan := _plan(spell, 1000.0)
	plan.set_infusion(&"poison", 6)
	assert_eq(plan.aspect_overrun(), 2, "6 points on a capacity-4 spell")


func test_points_on_a_refused_aspect_count() -> void:
	var spell := _SPARK.duplicate() as SpellDef
	spell.default_rate = 0.0
	var plan := _plan(spell, 10.0)
	plan.set_infusion(&"poison", 3)
	assert_eq(plan.aspect_overrun(), 3, "a 0-rate aspect takes no points")


# ── the remembered infusion, clamped to today ──────────────────────────

func test_clamp_infusion_refills_each_kept_aspect_to_what_it_holds() -> void:
	var plan := _plan(_VENOM, 100.0)
	plan.attacker.stat_board.facet(&"poison", StatDef.Role.ASPECT).base_value = 40.0
	var kept := ArmedStack.clamp_infusion(_VENOM, plan.attacker, {&"poison": 5})
	assert_eq(kept, {&"poison": 40} as Dictionary[StringName, int], "re-maxed to the held 40")


func test_clamp_infusion_drops_refused_and_past_the_slots() -> void:
	var spell := _VENOM.duplicate() as SpellDef
	spell.infusion_capacity = 30.0
	var plan := _plan(spell, 100.0)
	plan.attacker.stat_board.facet(&"poison", StatDef.Role.ASPECT).base_value = 40.0
	plan.attacker.stat_board.facet(&"wither", StatDef.Role.ASPECT).base_value = 5.0
	var refused := spell.duplicate() as SpellDef
	refused.default_rate = 0.0
	assert_true(ArmedStack.clamp_infusion(refused, plan.attacker, {&"curse": 1}).is_empty(),
			"a refused aspect is dropped")
	var kept := ArmedStack.clamp_infusion(spell, plan.attacker,
			{&"curse": 1, &"poison": 1, &"wither": 1})
	assert_eq(kept, {&"curse": 20, &"poison": 10} as Dictionary[StringName, int],
			"entry order, 2 slots, capacity 30 left after curse 20")
	var uncapped := ArmedStack.clamp_infusion(_VENOM, plan.attacker,
			{&"curse": 1, &"poison": 1, &"wither": 1})
	assert_eq(uncapped, {&"curse": 20, &"poison": 40} as Dictionary[StringName, int],
			"no capacity: the third aspect is dropped by the 2 slots alone")


func test_set_infusion_emits_state_changed() -> void:
	var plan := _plan(_SPARK, 10.0)
	watch_signals(plan)
	plan.set_infusion(&"poison", 2)
	assert_signal_emitted(plan, "state_changed")
	assert_eq(plan.infusion.points.get(&"poison", 0), 2)


func test_set_spell_resets_the_infusion() -> void:
	var plan := _plan(_SPARK, 10.0)
	plan.set_infusion(&"poison", 2)
	plan.set_spell(_VENOM)
	assert_true(plan.infusion.points.is_empty())


# ── the wire ────────────────────────────────────────────────────────────

func test_wire_round_trips_points() -> void:
	var plan := _plan(_SPARK, 10.0)
	plan.set_infusion(&"poison", 3)
	plan.set_infusion(&"curse", 1)
	var graph := plan.attacker.get_parent() as Graph
	var back := MagicAttackPlan.from_dict(plan.to_dict(graph), graph)
	assert_eq(back.infusion.points.get(&"poison", 0), 3)
	assert_eq(back.infusion.points.get(&"curse", 0), 1)


func test_an_uninfused_plan_ships_no_infusion_key() -> void:
	var plan := _plan(_SPARK, 10.0)
	var graph := plan.attacker.get_parent() as Graph
	assert_false(plan.to_dict(graph).has("infusion"))
	var back := MagicAttackPlan.from_dict(plan.to_dict(graph), graph)
	assert_not_null(back.infusion)
	assert_true(back.infusion.points.is_empty())
