extends GutTest

## [method InfusionChoices.entries]: the socket wheel's wedges — every aspect
## the caster holds, in roster order, with its held value, a check when it sits
## in another socket, a disabled reason when refused or out of capacity, and the
## exchange line "if socketed here". Plus the ghost socket's threshold:
## [method EntityStatBoard.next_threshold] over the `infusion_slots` ladder.

var h: SpellTestHelper


func before_each() -> void:
	h = SpellTestHelper.new()


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


func _by_id(entries: Array[AspectWheelEntry]) -> Dictionary:
	var out := {}
	for e in entries:
		out[e.id] = e
	return out


func test_only_held_aspects_in_roster_order_with_their_values() -> void:
	var plan := _plan(_caster({&"poison": 5, &"curse": 3}), _spell())
	var entries := InfusionChoices.entries(plan, 0)
	var ids: Array[StringName] = []
	for e in entries:
		ids.append(e.id)
	var expected: Array[StringName] = []
	for aspect in AspectRoster.shared().aspects:
		if aspect.id() in [&"poison", &"curse"]:
			expected.append(aspect.id())
	assert_eq(ids, expected, "held only, roster order")
	var by := _by_id(entries)
	assert_eq((by[&"poison"] as AspectWheelEntry).value, 5)
	assert_eq((by[&"curse"] as AspectWheelEntry).value, 3)
	assert_not_null((by[&"poison"] as AspectWheelEntry).identity, "tint and badge source")
	assert_eq((by[&"poison"] as AspectWheelEntry).hub_text,
			InfusionExchange.line(plan.spell, &"poison", 5), "the line if socketed here")


func test_a_refused_aspect_is_disabled_with_a_reason() -> void:
	var plan := _plan(_caster({&"poison": 5}), _spell(INF, 0.0))
	var e: AspectWheelEntry = InfusionChoices.entries(plan, 0)[0]
	assert_false(e.is_pickable())
	assert_string_contains(e.disabled_reason, "refused by Test Bolt")
	assert_eq(e.hub_text, "refused")


func test_an_aspect_in_another_socket_is_checked() -> void:
	var plan := _plan(_caster({&"poison": 5, &"curse": 3}), _spell())
	plan.set_socket(0, &"poison")
	var by := _by_id(InfusionChoices.entries(plan, 1))
	assert_true((by[&"poison"] as AspectWheelEntry).checked, "in socket 0")
	assert_false((by[&"curse"] as AspectWheelEntry).checked)
	var own := _by_id(InfusionChoices.entries(plan, 0))
	assert_false((own[&"poison"] as AspectWheelEntry).checked, "its own socket is not 'another'")


func test_exhausted_capacity_disables_and_the_line_reads_capacity_left() -> void:
	var plan := _plan(_caster({&"poison": 4, &"curse": 3}), _spell(6.0))
	plan.set_socket(0, &"poison")
	var by := _by_id(InfusionChoices.entries(plan, 1))
	assert_eq((by[&"curse"] as AspectWheelEntry).hub_text,
			InfusionExchange.line(plan.spell, &"curse", 2), "6 - 4 = 2 left")
	plan.set_socket(0, &"")
	var spell := _spell(4.0)
	var full := _plan(_caster({&"poison": 4, &"curse": 3}), spell)
	full.set_socket(0, &"poison")
	var curse: AspectWheelEntry = _by_id(InfusionChoices.entries(full, 1))[&"curse"]
	assert_false(curse.is_pickable(), "no capacity left")
	assert_string_contains(curse.disabled_reason.to_lower(), "capacity")


func test_next_threshold_walks_the_infusion_slots_ladder() -> void:
	for row in [[5.0, 10.0], [10.0, 100.0], [99.0, 100.0], [100.0, 1000.0]]:
		var board := _caster({}, row[0]).stat_board as EntityStatBoard
		assert_eq(board.next_threshold(&"infusion_slots"), row[1], "INT %d" % row[0])
	var top := _caster({}, 1000.0).stat_board as EntityStatBoard
	assert_eq(top.next_threshold(&"infusion_slots"), INF, "the cap: no ghost")
	assert_eq(top.next_threshold(&"strength"), INF, "no threshold formula derives it")


func test_next_breakpoint_is_the_first_unreached_rung() -> void:
	var f := ThresholdFormula.new()
	f.breakpoints = [10.0, 100.0]
	assert_eq(f.next_breakpoint(0.0), 10.0)
	assert_eq(f.next_breakpoint(10.0), 100.0, "reached at equality, as compute counts")
	assert_eq(f.next_breakpoint(100.0), INF)
