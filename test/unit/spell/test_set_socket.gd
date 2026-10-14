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
		board.facet(id, StatDef.Role.ASPECT).base_value = float(held[id])
	return atk


func _spell(capacity: float = INF, default_rate: float = 1.0) -> SpellDef:
	var spell := SpellDef.new()
	spell.name = "Test Bolt"
	spell.infusion_capacity = capacity
	spell.default_rate = default_rate
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
	var plan := _plan(_caster({&"poison": 5, &"curse": 3, &"hex": 2}), _spell())
	plan.set_socket(0, &"poison")
	plan.set_socket(1, &"curse")
	plan.set_socket(0, &"")
	assert_eq(_keys(plan), [&"curse"] as Array[StringName], "curse slid to socket 0")
	plan.set_socket(2, &"hex")
	assert_eq(_keys(plan), [&"curse", &"hex"] as Array[StringName], "index 2 with one filled appends at 1")


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
	var plan := _plan(_caster({&"poison": 3}), _spell(INF, 0.0))
	plan.set_socket(0, &"poison")
	assert_true(plan.infusion.points.is_empty(), "rate 0: refused")
	var plan2 := _plan(_caster({&"poison": 3}), _spell())
	plan2.set_socket(0, &"curse")
	assert_true(plan2.infusion.points.is_empty(), "curse not held")
	plan2.set_socket(0, &"poison")
	plan2.set_socket(0, &"curse")
	assert_eq(_keys(plan2), [&"poison"] as Array[StringName], "an unheld write never displaces")


func test_no_sequence_overruns() -> void:
	var plan := _plan(_caster({&"poison": 7, &"curse": 4, &"hex": 9}, 1000.0), _spell(10.0))
	var ids: Array[StringName] = [&"poison", &"curse", &"hex", &""]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1584
	for i in 200:
		plan.set_socket(rng.randi_range(0, 3), ids[rng.randi_range(0, ids.size() - 1)])
		assert_eq(plan.aspect_overrun(), 0, "overrun after step %d" % i)
		if plan.aspect_overrun() != 0:
			return
