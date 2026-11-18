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
	assert_eq(one.load_of(_CYCLONE).get(&"poison", 0), 0, "1 point at 1:2 floors to nothing")
	assert_eq(_rider_power(one, _CYCLONE, &"poison"), 0.0, "and lands no poison rider")
	var four := _infused(_CYCLONE, {&"poison": 4})
	assert_eq(four.load_of(_CYCLONE).get(&"poison", 0), 2, "4 points at 1:2 is 2")
	assert_eq(_rider_power(four, _CYCLONE, &"poison"), 2.0, "2 poison per landing")


func test_venom_ingests_at_double_rate_on_top_of_innate() -> void:
	var inf := _infused(_VENOM, {&"poison": 3})
	var aff: AspectIntake = _VENOM.intakes[0]
	var expected := aff.innate + floori(3.0 * aff.affinity_gain / aff.affinity_cost)
	assert_eq(Vector2i(aff.affinity_gain, aff.affinity_cost), Vector2i(2, 1), "fixture: the dose has 2:1 poison affinity")
	assert_eq(inf.load_of(_VENOM).get(&"poison", 0), expected, "innate + floor(3 x 2)")
	assert_eq(_rider_power(inf, _VENOM, &"poison"), float(expected))


func test_innate_infusion_spends_nothing() -> void:
	var inf := Infusion.innate(_VENOM)
	assert_true(inf.points.is_empty())
	assert_eq(inf.slots_used(), 0)
	assert_eq(inf.load_of(_VENOM).get(&"poison", 0), _VENOM.intakes[0].innate)


func test_slots_used_counts_aspects_with_points() -> void:
	var inf := _infused(_SPARK, {&"poison": 2, &"curse": 0, &"wither": 1})
	assert_eq(inf.slots_used(), 2)


# ── the plan's overrun ──────────────────────────────────────────────────

func _plan(spell: SpellDef, intelligence: float) -> MagicAttackPlan:
	var graph := h.make_graph([[0, 1]], self)
	var atk := h.make_entity(graph, "ATK", Color.RED)
	atk.stat_board.intelligence.base_value = intelligence
	atk.stat_board.facet(&"poison", StatDef.Role.COUNT).base_value = 20.0
	atk.stat_board.facet(&"curse", StatDef.Role.COUNT).base_value = 20.0
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
	plan.attacker.stat_board.facet(&"poison", StatDef.Role.COUNT).base_value = 2.0
	plan.set_infusion(&"poison", 5)
	assert_eq(plan.aspect_overrun(), 3, "5 poison on poison_aspect 2")


func test_each_aspect_carries_what_it_holds_with_no_pool() -> void:
	var plan := _plan(_VENOM, 100.0)
	plan.attacker.stat_board.facet(&"poison", StatDef.Role.COUNT).base_value = 40.0
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
	spell.ingest_gain = 0
	var plan := _plan(spell, 10.0)
	plan.set_infusion(&"poison", 3)
	assert_eq(plan.aspect_overrun(), 3, "a 0-rate aspect takes no points")


# ── the remembered infusion, clamped to today ──────────────────────────

func test_clamp_infusion_refills_each_kept_aspect_to_what_it_holds() -> void:
	var plan := _plan(_VENOM, 100.0)
	plan.attacker.stat_board.facet(&"poison", StatDef.Role.COUNT).base_value = 40.0
	var kept := ArmedStack.clamp_infusion(_VENOM, plan.attacker, {&"poison": 5})
	assert_eq(kept, {&"poison": 40} as Dictionary[StringName, int], "re-maxed to the held 40")


func test_clamp_infusion_drops_refused_and_past_the_slots() -> void:
	var spell := _VENOM.duplicate() as SpellDef
	spell.infusion_capacity = 30.0
	var plan := _plan(spell, 100.0)
	plan.attacker.stat_board.facet(&"poison", StatDef.Role.COUNT).base_value = 40.0
	plan.attacker.stat_board.facet(&"wither", StatDef.Role.COUNT).base_value = 5.0
	var refused := spell.duplicate() as SpellDef
	refused.ingest_gain = 0
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
	var back := MagicAttackPlan.from_dict(plan.to_dict(graph), graph, TestSpells.CATALOG)
	assert_eq(back.infusion.points.get(&"poison", 0), 3)
	assert_eq(back.infusion.points.get(&"curse", 0), 1)


func test_an_uninfused_plan_ships_no_infusion_key() -> void:
	var plan := _plan(_SPARK, 10.0)
	var graph := plan.attacker.get_parent() as Graph
	assert_false(plan.to_dict(graph).has("infusion"))
	var back := MagicAttackPlan.from_dict(plan.to_dict(graph), graph, TestSpells.CATALOG)
	assert_not_null(back.infusion)
	assert_true(back.infusion.points.is_empty())


# ── the ride row's rekeying (#1800): a row named by element resolves its status ──

const _HEAT: StatusDef = preload("res://effects/status/heat.tres")


func _fire_row_spell(plants: StatusDef, innate: int) -> SpellDef:
	var spell := SpellDef.new()
	var row := AspectIntake.new()
	row.identity = ElementRoster.shared().by_id(&"fire").identity
	row.plants = plants
	row.innate = innate
	spell.intakes = [row]
	return spell


func test_a_fire_row_planting_heat_gives_one_heat_rider_at_its_innate() -> void:
	var spell := _fire_row_spell(_HEAT, 3)
	var riders := Infusion.innate(spell).bag(spell).riders
	assert_eq(riders.size(), 1)
	var apply := riders[0] as ApplyStatusEffect
	assert_not_null(apply)
	assert_eq(apply.def, _HEAT)
	assert_eq(apply.power, 3.0)


func test_a_fire_row_with_plants_unset_resolves_the_elements_terrain() -> void:
	var spell := _fire_row_spell(null, 3)
	var riders := Infusion.innate(spell).bag(spell).riders
	assert_eq(riders.size(), 1)
	var apply := riders[0] as ApplyStatusEffect
	assert_not_null(apply)
	assert_eq(apply.def, _HEAT)
	assert_eq(apply.power, 3.0)


func test_a_fire_rows_load_keys_fire_and_its_use_plants() -> void:
	var spell := _fire_row_spell(_HEAT, 3)
	assert_eq(Infusion.innate(spell).load_of(spell), {&"fire": 3})
	assert_true(Infusion.use_of(spell, &"fire") is PlantUse)


func test_a_poison_row_with_plants_unset_still_resolves_by_concept() -> void:
	var spell := SpellDef.new()
	var row := AspectIntake.new()
	row.identity = StatusRoster.shared().by_concept(&"poison").identity
	row.innate = 2
	spell.intakes = [row]
	assert_eq(row.status(), StatusRoster.shared().by_concept(&"poison"))
	assert_eq(_rider_power(Infusion.innate(spell), spell, &"poison"), 2.0)


# ── the shape and the ride (ADR 0085 §1, ADR 0094 §6) ───────────────────

const _CHARGE: StatusDef = preload("res://effects/status/charge.tres")
const _COLD: StatusDef = preload("res://effects/status/cold.tres")
const _LIGHTNING_BOLT: SpellDef = preload("res://attack/spell/defs/lightning_bolt.tres")
const _ELEMENTS: Array[StringName] = [&"fire", &"ice", &"lightning"]


## A spell whose one intake row is an innate Charge ride of [param innate].
func _charge_ride_spell(innate: int) -> SpellDef:
	var spell := SpellDef.new()
	var row := AspectIntake.new()
	row.identity = ElementRoster.shared().by_id(&"lightning").identity
	row.plants = _CHARGE
	row.innate = innate
	spell.intakes = [row]
	return spell


func _rider(inf: Infusion, spell: SpellDef, def: StatusDef) -> float:
	for rider in inf.bag(spell).riders:
		var apply := rider as ApplyStatusEffect
		if apply != null and apply.def == def:
			return apply.power
	return 0.0


func test_a_ride_of_the_innate_element_adds_to_its_load() -> void:
	var spell := _charge_ride_spell(2)
	var inf := Infusion.innate(spell)
	inf.set_ride(&"lightning", 3)
	assert_eq(inf.load_of(spell).get(&"lightning", 0),
			2 + Infusion.gained(spell, &"lightning", 3), "innate + gained(ride_points)")
	assert_eq(_rider(inf, spell, _CHARGE), float(2 + Infusion.gained(spell, &"lightning", 3)))


func test_a_ride_of_another_element_replaces_the_innate_one() -> void:
	var spell := _charge_ride_spell(2)
	var inf := Infusion.innate(spell)
	inf.set_ride(&"fire", 3)
	var load := inf.load_of(spell)
	assert_eq(load.get(&"lightning", 0), 0, "the innate Charge is suppressed for this cast")
	assert_eq(load.get(&"fire", 0), Infusion.gained(spell, &"fire", 3), "Heat at its row's ratio")
	assert_eq(Infusion.gained(spell, &"fire", 3), 3, "unlisted trades 1:1")
	assert_eq(_rider(inf, spell, _CHARGE), 0.0, "no Charge rider: one element per hit")
	assert_eq(_rider(inf, spell, _HEAT), 3.0)


func test_a_replacing_ride_leaves_the_def_untouched() -> void:
	var spell := _charge_ride_spell(2)
	var rows := spell.intakes.duplicate()
	var inf := Infusion.innate(spell)
	inf.set_ride(&"fire", 3)
	inf.bag(spell)
	assert_eq(spell.intakes, rows, "same rows")
	assert_eq(spell.intakes[0].innate, 2, "same innate")
	assert_eq(Infusion.innate(spell).load_of(spell), {&"lightning": 2}, "the next cast is innate again")


func test_ride_of_answers_forged_then_innate_then_empty() -> void:
	var spell := _charge_ride_spell(1)
	var inf := Infusion.innate(spell)
	assert_eq(inf.ride_of(spell), &"lightning", "innate")
	inf.set_ride(&"ice", 1)
	assert_eq(inf.ride_of(spell), &"ice", "forged")
	inf.set_ride(&"ice", 0)
	assert_eq(inf.ride_of(spell), &"lightning", "0 points is nothing forged")
	assert_eq(Infusion.innate(_SPARK).ride_of(_SPARK), &"", "no ride row, nothing forged")


func test_shape_of_answers_forged_else_empty() -> void:
	var inf := Infusion.innate(_SPARK)
	assert_eq(inf.shape_of(_SPARK), &"")
	inf.set_shape(&"fire", 2)
	assert_eq(inf.shape_of(_SPARK), &"fire")
	inf.set_shape(&"", 2)
	assert_eq(inf.shape_of(_SPARK), &"", "an empty id clears")


func test_spent_on_sums_shape_and_ride_of_one_element() -> void:
	var inf := Infusion.innate(_SPARK)
	inf.set_shape(&"fire", 2)
	inf.set_ride(&"fire", 3)
	assert_eq(inf.spent_on(&"fire"), 5)
	inf.set_ride(&"ice", 3)
	assert_eq(inf.spent_on(&"fire"), 2)
	assert_eq(inf.spent_on(&"ice"), 3)


func test_neither_field_takes_a_slot_or_counts_in_the_total() -> void:
	var inf := _infused(_VENOM, {&"poison": 4, &"curse": 2})
	var slots := inf.slots_used()
	var total := inf.total_points()
	inf.set_shape(&"fire", 3)
	inf.set_ride(&"ice", 5)
	assert_eq(inf.shape_points, 3, "full aspect sockets still take a shape")
	assert_eq(inf.ride_points, 5, "and a ride")
	assert_eq(inf.slots_used(), slots)
	assert_eq(inf.total_points(), total, "the aspects alone")
	assert_eq(total, 6)


func test_rebuilt_keeps_the_fields() -> void:
	var inf := Infusion.innate(_SPARK)
	inf.set_shape(&"fire", 2)
	inf.set_ride(&"ice", 1)
	var next := inf.rebuilt(_SPARK, {&"poison": 1})
	assert_eq([next.shape_element, next.shape_points, next.ride_element, next.ride_points],
			[&"fire", 2, &"ice", 1])
	assert_eq(next.points, {&"poison": 1} as Dictionary[StringName, int])


func _bolt_board() -> Dictionary:
	var graph := h.make_graph([[0, 1], [1, 2], [2, 3]], self)
	var atk := h.make_entity(graph, "A")
	var def := h.make_entity(graph, "D")
	h.give_big_hp(def)
	h.assign_owner(graph, def, [1, 2, 3])
	h.assign_owner(graph, atk, [0])
	atk.stat_board.get_stat(&"crit_chance").base_value = 0.0
	return {graph = graph, atk = atk, n = graph.get_skill_nodes()}


func _damage_by_node(outcome: AttackOutcome) -> Dictionary:
	var out := {}
	for node in h.hits_by_node(outcome):
		out[node] = h.total_damage_on(outcome, node)
	return out


func test_the_shape_is_inert_on_the_walk_the_seed_and_the_load() -> void:
	var spell := _LIGHTNING_BOLT
	var hops: float = spell.propagation.max_hops
	var plain := Infusion.innate(spell)
	for element in _ELEMENTS:
		var b := _bolt_board()
		var shaped := Infusion.innate(spell)
		shaped.set_shape(element, 3)
		assert_eq(shaped.load_of(spell), plain.load_of(spell), "%s: same load" % element)
		assert_eq(shaped.bag(spell).riders.size(), plain.bag(spell).riders.size(), "%s: same bag" % element)
		assert_eq(_rider(shaped, spell, _CHARGE), _rider(plain, spell, _CHARGE), "%s: same Charge" % element)
		var n: Array = b.n
		var with_shape := SpellResolver.resolve(spell, n[1], n[0], b.atk, b.graph, null, shaped)
		var without := SpellResolver.resolve(spell, n[1], n[0], b.atk, b.graph, null, plain)
		assert_eq(_damage_by_node(with_shape), _damage_by_node(without), "%s: same walk and payload" % element)
		assert_eq(spell.propagation.max_hops, hops, "%s: max_hops untouched" % element)


func test_an_ice_ride_leaves_max_hops_and_lands_cold_at_the_ice_load() -> void:
	var spell := _LIGHTNING_BOLT
	var hops: float = spell.propagation.max_hops
	var inf := Infusion.innate(spell)
	inf.set_ride(&"ice", 2)
	assert_eq(spell.propagation.max_hops, hops)
	var ice_load: int = inf.load_of(spell).get(&"ice", 0)
	assert_eq(ice_load, Infusion.gained(spell, &"ice", 2))
	assert_eq(_rider(inf, spell, _COLD), float(ice_load), "Cold riders at the Ice load")
	assert_eq(_rider(inf, spell, _CHARGE), 0.0, "the innate Charge gives way")
