extends GutTest

## [method MagicAttackPlan.set_socket]: the plan owns socket order — the
## insertion order of `infusion.points`. One aspect per socket, never two
## sockets of one aspect, sockets compact, and each socket's depth is
## `min(held, capacity left)` walked front to back. No pool (#1583).

var h: SpellTestHelper


func before_each() -> void:
	h = SpellTestHelper.new()


## INT [param intelligence] (100 → 1 slot, 1000 → 2, 10000 → 3); every aspect
## zeroed but those in [param held] (`{aspect id: amount}`).
func _caster(held: Dictionary, intelligence: float = 10000.0) -> Entity:
	var graph := h.make_graph([[0, 1]], self)
	var atk := h.make_entity(graph, "ATK", Color.RED)
	var board := atk.stat_board
	board.intelligence.base_value = intelligence
	for aspect in AspectRoster.shared().aspects:
		if aspect.stat != null and board.get_stat(aspect.stat.id) != null:
			board.get_stat(aspect.stat.id).base_value = 0.0
	for id in held:
		board.facet(id, StatDef.Role.COUNT).base_value = float(held[id])
	return atk


func _spell(capacity: float = INF, ingest_gain: int = 1) -> SpellDef:
	var spell := SpellDef.new()
	spell.name = "Test Bolt"
	spell.infusion_capacity = capacity
	spell.ingest_gain = ingest_gain
	return spell


func _plan(caster: Entity, spell: SpellDef) -> MagicAttackPlan:
	var plan := MagicAttackPlan.new()
	plan.attacker = caster
	plan.set_spell(spell)
	return plan


func _keys(plan: MagicAttackPlan) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(plan.infusion.points.keys())
	return out


func test_a_second_socket_appends_in_socket_order() -> void:
	var plan := _plan(_caster({&"poison": 5, &"curse": 3}), _spell())
	plan.set_socket(0, &"poison")
	plan.set_socket(1, &"curse")
	assert_eq(_keys(plan), [&"poison", &"curse"] as Array[StringName])
	assert_eq(plan.infusion.points[&"poison"], 5, "depth = held")
	assert_eq(plan.infusion.points[&"curse"], 3, "depth = held")


func test_an_aspect_in_another_socket_moves_and_displaces() -> void:
	var plan := _plan(_caster({&"poison": 5, &"curse": 3}), _spell())
	plan.set_socket(0, &"poison")
	plan.set_socket(1, &"curse")
	plan.set_socket(0, &"curse")
	assert_eq(_keys(plan), [&"curse"] as Array[StringName], "never two of one aspect; poison displaced")


func test_clearing_a_socket_compacts_and_a_gap_appends() -> void:
	var plan := _plan(_caster({&"poison": 5, &"curse": 3, &"mark": 2}), _spell())
	plan.set_socket(0, &"poison")
	plan.set_socket(1, &"curse")
	plan.set_socket(0, &"")
	assert_eq(_keys(plan), [&"curse"] as Array[StringName], "curse slid to socket 0")
	plan.set_socket(2, &"mark")
	assert_eq(_keys(plan), [&"curse", &"mark"] as Array[StringName], "index 2 with one filled appends at 1")


func test_depth_is_min_of_held_and_capacity_left_and_refills_on_clear() -> void:
	var plan := _plan(_caster({&"poison": 3, &"curse": 4}), _spell(4.0))
	plan.set_socket(0, &"poison")
	plan.set_socket(1, &"curse")
	assert_eq(plan.infusion.points[&"poison"], 3)
	assert_eq(plan.infusion.points[&"curse"], 1, "capacity 4 leaves 1")
	plan.set_socket(0, &"")
	assert_eq(plan.infusion.points[&"curse"], 4, "clearing poison lets curse refill")


func test_one_state_changed_per_call_and_none_on_a_no_op() -> void:
	var plan := _plan(_caster({&"poison": 3}), _spell())
	watch_signals(plan)
	plan.set_socket(0, &"poison")
	assert_signal_emit_count(plan, "state_changed", 1)
	plan.set_socket(0, &"poison")
	assert_signal_emit_count(plan, "state_changed", 1, "unchanged: no emit")


func test_full_slots_refuse_a_new_aspect() -> void:
	var plan := _plan(_caster({&"poison": 3, &"curse": 3}, 10.0), _spell())
	plan.set_socket(0, &"poison")
	plan.set_socket(1, &"curse")
	assert_eq(_keys(plan), [&"poison"] as Array[StringName], "INT 10 owns one socket")


func test_a_refused_or_unheld_aspect_never_lands() -> void:
	var plan := _plan(_caster({&"poison": 3}), _spell(INF, 0))
	plan.set_socket(0, &"poison")
	assert_true(plan.infusion.points.is_empty(), "rate 0: refused")
	var plan2 := _plan(_caster({&"poison": 3}), _spell())
	plan2.set_socket(0, &"curse")
	assert_true(plan2.infusion.points.is_empty(), "curse not held")
	plan2.set_socket(0, &"poison")
	plan2.set_socket(0, &"curse")
	assert_eq(_keys(plan2), [&"poison"] as Array[StringName], "an unheld write never displaces")


func test_no_sequence_overruns() -> void:
	var plan := _plan(_caster({&"poison": 7, &"curse": 4, &"mark": 9}, 1000.0), _spell(10.0))
	var ids: Array[StringName] = [&"poison", &"curse", &"mark", &""]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1584
	for i in 200:
		plan.set_socket(rng.randi_range(0, 3), ids[rng.randi_range(0, ids.size() - 1)])
		assert_eq(plan.aspect_overrun(), 0, "overrun after step %d" % i)
		if plan.aspect_overrun() != 0:
			return


# ── overqualified casting: the cap in force ──────────────────────────────
#
# A board where the casters differ in capacity. ATK owns n0 - n1 - n2 (owned
# degrees 1 / 2 / 1); hostile targets t3 (reached by n1 and n2), t4 (n1 only)
# and t5 (n0 only), each one hop out (a 0-hop finder: the board's own
# `cast_range_hops` adds the one). A min_degree-1 spell: n0 and n2 carry
# the base cap B, n1 carries B + K. n2 is the strongest caster, so it is
# t3's pick at 0 points.

const _B := 4.0
const _K := 3

var _n: Array[SkillNode] = []


func _board_caster() -> Entity:
	var graph := h.make_graph([[0, 1], [1, 2], [2, 3], [1, 3], [1, 4], [0, 5]], self)
	var atk := h.make_entity(graph, "ATK", Color.RED)
	var def := h.make_entity(graph, "DEF", Color.BLUE)
	h.assign_owner(graph, atk, [0, 1, 2])
	h.assign_owner(graph, def, [3, 4, 5])
	_n.assign(graph.get_skill_nodes())
	var flat := StatModifier.new()
	flat.stat_id = &"spell_damage"
	flat.operation = StatModifier.Operation.ADD_BASE
	flat.value = 50.0
	_n[2].add_local_modifier(flat)
	var board := atk.stat_board
	board.intelligence.base_value = 100.0
	for aspect in AspectRoster.shared().aspects:
		if aspect.stat != null and board.get_stat(aspect.stat.id) != null:
			board.get_stat(aspect.stat.id).base_value = 0.0
	for id in [&"poison", &"curse", &"mark"]:
		board.facet(id, StatDef.Role.COUNT).base_value = 20.0
	return atk


func _board_spell(aimed: bool = false) -> SpellDef:
	var spell := _spell(_B)
	spell.min_degree = 1
	spell.infusion_capacity_per_degree = _K
	if aimed:
		var a := AimedTargeting.new()
		a.shape = LineShape.new()
		a.ownership_filter = SkillNode.Ownership.HOSTILE
		a.range_finder = EuclideanRangeFinder.new()
		a.range_finder.max_distance = 450.0
		spell.targeting = a
	else:
		var t := NodeTargeting.new()
		t.ownership_filter = SkillNode.Ownership.HOSTILE
		var f := HopRangeFinder.new()
		f.max_hops = 0
		t.range_finder = f
		spell.targeting = t
	return spell


func _board_plan(aimed: bool = false) -> MagicAttackPlan:
	return _plan(_board_caster(), _board_spell(aimed))


func _base(plan: MagicAttackPlan) -> int:
	return plan.spell.capacity_at(plan.spell.min_degree)


func _over(plan: MagicAttackPlan) -> int:
	return plan.spell.capacity_at(plan.spell.min_degree + 1)


func test_fixture_capacities() -> void:
	var plan := _board_plan()
	var u := plan.union()
	assert_eq(u.best_capacity(_n[3]), _over(plan))
	assert_eq(u.best_capacity(_n[4]), _over(plan))
	assert_eq(u.best_capacity(_n[5]), _base(plan))
	assert_eq(u.source_for(_n[3]), _n[2], "the strongest caster picks t3 at 0 points")


func test_with_no_target_a_socket_fills_to_the_best_eligible_capacity() -> void:
	var plan := _board_plan()
	plan.set_socket(0, &"poison")
	assert_eq(plan.infusion.total_points(), _over(plan))
	assert_eq(plan.capacity(), _over(plan))


func test_with_a_base_only_target_a_socket_fills_to_the_base_cap() -> void:
	var plan := _board_plan()
	assert_true(plan.set_target(_n[5]))
	plan.set_socket(0, &"poison")
	assert_eq(plan.infusion.total_points(), _base(plan))
	assert_eq(plan.aspect_overrun(), 0)


func test_a_write_past_the_source_cap_re_picks_a_carrying_caster() -> void:
	var plan := _board_plan()
	plan.set_target(_n[3])
	assert_eq(plan.source, _n[2], "fixture: picked from the base-degree caster")
	plan.set_socket(0, &"poison")
	assert_eq(plan.target, _n[3], "the target stays")
	assert_eq(plan.source, _n[1], "the source moves to the caster that carries it")
	assert_eq(plan.infusion.total_points(), _over(plan))
	assert_eq(plan.aspect_overrun(), 0)
	var before := [plan.infusion.points.duplicate(), plan.infusion.points.keys(), plan.source]
	plan.set_socket(1, &"curse")
	assert_eq([plan.infusion.points.duplicate(), plan.infusion.points.keys(), plan.source], before,
			"at the target's best capacity a further write changes nothing")


func test_an_aimed_plan_never_moves_its_source() -> void:
	var plan := _board_plan(true)
	assert_true(plan.set_aim(_n[2], 0.0))
	plan.set_socket(0, &"poison")
	assert_eq(plan.source, _n[2])
	assert_eq(plan.infusion.total_points(), _base(plan), "refused past the locked caster's cap")
	assert_eq(plan.aspect_overrun(), 0)


func test_a_pick_below_the_loadout_trims_it_once() -> void:
	var plan := _board_plan()
	var p := _over(plan)
	plan.set_infusion(&"poison", p)
	watch_signals(plan)
	assert_true(plan.set_target(_n[5]), "a red target stays pickable")
	var c := _base(plan)
	assert_eq(plan.infusion.total_points(), c)
	assert_eq(plan.aspect_overrun(), 0)
	assert_eq(plan.source, plan.union().source_for(_n[5], c))
	assert_true(plan.is_target_muted())
	assert_signal_emit_count(plan, "loadout_trimmed", 1)
	assert_signal_emitted_with_parameters(plan, "loadout_trimmed", [p, c])
	plan.set_target(_n[4])
	assert_eq(plan.infusion.total_points(), c, "one-shot: a higher-cap target refills nothing")
	assert_false(plan.is_target_muted(), "a target change clears the mark")
	assert_signal_emit_count(plan, "loadout_trimmed", 1)


func test_a_pick_that_carries_the_loadout_trims_nothing() -> void:
	var plan := _board_plan()
	var p := _over(plan)
	plan.set_infusion(&"poison", p)
	watch_signals(plan)
	plan.set_target(_n[4])
	assert_eq(plan.infusion.total_points(), p)
	assert_signal_not_emitted(plan, "loadout_trimmed")
	assert_false(plan.is_target_muted())


func test_aiming_trims_nothing_and_the_lock_trims_once() -> void:
	var plan := _board_plan(true)
	var p := _over(plan)
	plan.set_infusion(&"poison", p)
	watch_signals(plan)
	plan.set_aim(_n[2], 0.0)
	plan.set_aim(_n[2], 0.5)
	assert_eq(plan.infusion.total_points(), p, "dragging trims nothing")
	assert_signal_not_emitted(plan, "loadout_trimmed")
	assert_true(plan.trim_to_source())
	assert_eq(plan.infusion.total_points(), _base(plan))
	assert_eq(plan.aspect_overrun(), 0)
	assert_signal_emit_count(plan, "loadout_trimmed", 1)
	assert_signal_emitted_with_parameters(plan, "loadout_trimmed", [p, _base(plan)])


func _loadout(plan: MagicAttackPlan) -> void:
	plan.set_infusion(&"poison", 5)
	plan.set_infusion(&"curse", 5)
	plan.set_infusion(&"mark", 4)
	plan.set_shape(&"fire", 2)
	plan.set_ride(&"ice", 3)


func test_trim_eats_the_last_aspect_first_and_spares_the_fields() -> void:
	var plan := _board_plan()
	_loadout(plan)
	plan.trim_to(10)
	assert_eq(plan.infusion.points, {&"poison": 5, &"curse": 5} as Dictionary[StringName, int],
			"the last entry popped at zero")
	plan.trim_to(8)
	assert_eq(plan.infusion.points, {&"poison": 5, &"curse": 3} as Dictionary[StringName, int])
	assert_eq([plan.infusion.shape_element, plan.infusion.shape_points,
			plan.infusion.ride_element, plan.infusion.ride_points], [&"fire", 2, &"ice", 3],
			"the shape and the ride are never trimmed")


func test_the_pick_trim_and_trim_to_agree() -> void:
	var picked := _board_plan()
	_loadout(picked)
	picked.set_target(_n[4])
	var trimmed := _board_plan()
	_loadout(trimmed)
	trimmed.trim_to(trimmed.union().best_capacity(_n[4]))
	assert_eq(picked.infusion.points, trimmed.infusion.points)
	assert_eq(picked.infusion.points.keys(), trimmed.infusion.points.keys())


func test_a_loadout_or_hover_change_rebuilds_no_union() -> void:
	var plan := _board_plan()
	var u := plan.union()
	plan.set_socket(0, &"poison")
	plan.set_infusion(&"curse", 2)
	plan.set_hover_target(_n[4])
	plan.set_hover_target(null)
	assert_same(plan.union(), u)


func test_reset_to_base_capacity_is_one_shot() -> void:
	var plan := _board_plan()
	plan.set_target(_n[4])
	plan.set_socket(0, &"poison")
	assert_eq(plan.infusion.total_points(), _over(plan), "fixture: filled past base")
	plan.reset_to_base_capacity()
	assert_lte(plan.infusion.total_points(), _base(plan))
	assert_eq(plan.aspect_overrun(), 0)
	plan.set_socket(1, &"curse")
	assert_gt(plan.infusion.total_points(), _base(plan), "the next write walks the cap in force again")


func test_the_pip_shows_overclock_potential() -> void:
	var plan := _board_plan()
	var k := _over(plan) - _base(plan)
	plan.set_infusion(&"poison", _over(plan))
	assert_eq(plan.get_node_pip(_n[4]), k)
	assert_false(plan.is_node_pip_red(_n[4]))
	assert_eq(plan.get_node_pip(_n[5]), 0, "only base-degree casters reach it")
	plan.set_infusion(&"poison", _over(plan) + 1)
	assert_true(plan.is_node_pip_red(_n[4]))
	assert_true(plan.set_target(_n[4]), "a red target stays pickable")
