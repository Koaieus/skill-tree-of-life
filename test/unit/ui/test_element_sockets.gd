extends GutTest

## The forge's two element sockets beside the aspect sockets: the shape socket
## and the ride socket each show their field ([method Infusion.shape_of] /
## [method Infusion.ride_of]), mark a pick as adds / replaces against that
## field's authored default, grey a refused element in the ride socket only,
## and offer an element's count less the other socket's spend on it.

const _BOLT: SpellDef = preload("res://attack/spell/defs/lightning_bolt.tres")
const _SPARK: SpellDef = preload("res://attack/spell/defs/spark.tres")
const _SOCKETS_SCENE := preload("res://ui/hud/command_tray/bodies/infusion_sockets.tscn")

const SHAPE := InfusionChoices.SHAPE_SOCKET
const RIDE := InfusionChoices.RIDE_SOCKET

var h: SpellTestHelper


func before_each() -> void:
	h = SpellTestHelper.new()


## Every aspect zeroed but poison ([param poison]); each element holds
## [param counts]' entry (0 when absent); INT [param intelligence].
func _caster(counts: Dictionary = {}, intelligence: float = 100.0, poison: float = 2.0) -> Entity:
	var graph := h.make_graph([[0, 1]], self)
	var atk := h.make_entity(graph, "ATK", Color.RED)
	var board := atk.stat_board
	board.intelligence.base_value = intelligence
	for aspect in AspectRoster.shared().aspects:
		if aspect.stat != null and board.get_stat(aspect.stat.id) != null:
			board.get_stat(aspect.stat.id).base_value = 0.0
	board.facet(&"poison", StatDef.Role.COUNT).base_value = poison
	for element in ElementRoster.shared().elements:
		board.get_stat(element.stat.id).base_value = float(counts.get(element.id(), 0))
	return atk


func _plan(caster: Entity, spell: SpellDef = _BOLT) -> MagicAttackPlan:
	var plan := MagicAttackPlan.new()
	plan.attacker = caster
	plan.set_spell(spell)
	return plan


func _entry(plan: MagicAttackPlan, field: int, id: StringName) -> AspectWheelEntry:
	for e in InfusionChoices.entries(plan, field):
		if e.id == id:
			return e
	return null


func _count(caster: Entity, id: StringName) -> int:
	return AspectCurrency.cap_of(caster, AspectCurrency.stat_of(id))


## A copy of spark whose one ride row is [param id] at rate 0.
func _refusing(id: StringName) -> SpellDef:
	var spell: SpellDef = _SPARK.duplicate()
	var row := AspectIntake.new()
	row.identity = ElementRoster.shared().by_id(id).identity
	row.affinity_gain = 0
	var rows: Array[AspectIntake] = [row]
	spell.intakes = rows
	return spell


# ── AC2: what each socket shows, and its marks ──────────────────────────────

func test_nothing_forged_each_socket_shows_its_field() -> void:
	var plan := _plan(_caster({&"fire": 3, &"lightning": 3}))
	var sockets: InfusionSockets = _SOCKETS_SCENE.instantiate()
	add_child_autofree(sockets)
	sockets.bind(plan)
	assert_eq(plan.infusion.ride_of(plan.spell), &"lightning", "lightning_bolt's innate ride")
	assert_eq(sockets.socket(RIDE).shown_id, plan.infusion.ride_of(plan.spell), "the ride socket shows ride_of")
	assert_eq(sockets.socket(SHAPE).shown_id, plan.infusion.shape_of(plan.spell), "the shape socket shows shape_of")
	assert_eq(sockets.socket(SHAPE).state, InfusionSocket.State.EMPTY, "no v1 shape default")
	assert_eq(sockets.socket_count(), AspectCurrency.cap_of(plan.attacker, &"infusion_slots"),
			"the element sockets are not counted among the aspect sockets")


func test_ride_marks_against_the_innate_ride() -> void:
	var plan := _plan(_caster({&"fire": 3, &"lightning": 3}))
	assert_eq(_entry(plan, RIDE, &"fire").mark, AspectWheelEntry.MARK_REPLACES, "Heat over Charge replaces")
	assert_eq(_entry(plan, RIDE, &"lightning").mark, AspectWheelEntry.MARK_ADDS, "Charge on Charge adds")
	for e in InfusionChoices.entries(plan, SHAPE):
		assert_eq(e.mark, AspectWheelEntry.MARK_NONE, "%s: no shape default to mark against" % e.id)
	var plain := _plan(_caster({&"fire": 3}), _SPARK)
	for e in InfusionChoices.entries(plain, RIDE):
		assert_eq(e.mark, AspectWheelEntry.MARK_NONE, "%s: no ride default to mark against" % e.id)


func test_element_sockets_offer_the_three_elements_only() -> void:
	var plan := _plan(_caster({&"fire": 1}))
	for field in [SHAPE, RIDE]:
		var ids := InfusionChoices.entries(plan, field).map(func(e: AspectWheelEntry) -> StringName: return e.id)
		var want := ElementRoster.shared().elements.map(func(e: Element) -> StringName: return e.id())
		assert_eq(ids, want, "field %d offers the roster's elements" % field)


func test_shape_and_ride_are_independent() -> void:
	var plan := _plan(_caster({&"fire": 3, &"ice": 3}))
	assert_true(InfusionChoices.pick_element(plan, RIDE, &"ice"), "ride pick")
	var ride := plan.infusion.ride_of(plan.spell)
	assert_true(InfusionChoices.pick_element(plan, SHAPE, &"fire"), "shape pick")
	assert_eq(plan.infusion.ride_of(plan.spell), ride, "setting the shape leaves the ride")
	var shape := plan.infusion.shape_of(plan.spell)
	assert_true(InfusionChoices.pick_element(plan, RIDE, &"fire"), "ride re-pick")
	assert_eq(plan.infusion.shape_of(plan.spell), shape, "setting the ride leaves the shape")


func test_element_sockets_take_a_pick_with_aspect_sockets_full() -> void:
	var full := _plan(_caster({&"fire": 2}, 10.0))
	full.set_socket(0, &"poison")
	assert_eq(full.infusion.slots_used(), AspectCurrency.cap_of(full.attacker, &"infusion_slots"), "aspects full")
	var before := full.infusion.slots_used()
	assert_true(InfusionChoices.pick_element(full, SHAPE, &"fire"), "shape takes a pick")
	assert_true(InfusionChoices.pick_element(full, RIDE, &"fire"), "ride takes a pick")
	assert_eq(full.infusion.slots_used(), before, "no aspect slot taken")
	var none := _plan(_caster({&"fire": 2}, 1.0))
	assert_eq(AspectCurrency.cap_of(none.attacker, &"infusion_slots"), 0, "a caster with 0 slots")
	assert_true(InfusionChoices.pick_element(none, SHAPE, &"fire"), "shape takes a pick at 0 slots")
	assert_true(InfusionChoices.pick_element(none, RIDE, &"fire"), "ride takes a pick at 0 slots")
	assert_eq(none.infusion.slots_used(), 0, "slots_used unchanged")


func test_a_repick_steps_one_point_up_to_the_offer() -> void:
	var plan := _plan(_caster({&"fire": 2}))
	InfusionChoices.pick_element(plan, SHAPE, &"fire")
	assert_eq(plan.infusion.shape_points, 1, "a first pick forges one point")
	InfusionChoices.pick_element(plan, SHAPE, &"fire")
	assert_eq(plan.infusion.shape_points, 2, "a re-pick adds one")
	InfusionChoices.pick_element(plan, SHAPE, &"fire")
	assert_eq(plan.infusion.shape_points, _count(plan.attacker, &"fire"), "never past the count")


func test_right_click_clears_the_ride_only() -> void:
	var plan := _plan(_caster({&"fire": 2}, 100.0))
	plan.set_socket(0, &"poison")
	InfusionChoices.pick_element(plan, RIDE, &"fire")
	var points := plan.infusion.points.duplicate()
	var sockets: InfusionSockets = _SOCKETS_SCENE.instantiate()
	add_child_autofree(sockets)
	sockets.bind(plan)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	sockets.socket(RIDE)._gui_input(ev)
	assert_eq(plan.infusion.ride_points, 0, "the ride is cleared")
	assert_eq(plan.infusion.points, points, "the aspects untouched")
	assert_eq(plan.infusion.slots_used(), points.size(), "slots_used untouched")


# ── AC3: ride refusal ───────────────────────────────────────────────────────

func test_ride_socket_greys_a_refused_element_and_ignores_its_pick() -> void:
	var spell := _refusing(&"fire")
	var plan := _plan(_caster({&"fire": 3}), spell)
	assert_true(Infusion.rate_of(spell, &"fire") <= 0.0, "the fixture refuses fire")
	var e := _entry(plan, RIDE, &"fire")
	assert_false(e.is_pickable(), "greyed in the ride socket")
	assert_string_contains(e.disabled_reason, spell.name, "the reason names the spell")
	var ride := plan.infusion.ride_of(spell)
	var element := plan.infusion.ride_element
	assert_false(InfusionChoices.pick_element(plan, RIDE, &"fire"), "the pick is refused")
	assert_eq(plan.infusion.ride_of(spell), ride, "ride_of unchanged")
	assert_eq(plan.infusion.ride_element, element, "no forged ride element")
	assert_eq(plan.infusion.ride_points, 0, "no forged ride points")
	assert_true(_entry(plan, SHAPE, &"fire").is_pickable(), "the shape socket does not grey it")


# ── AC3a: one count, two sockets ────────────────────────────────────────────

func test_one_count_feeds_both_sockets() -> void:
	var caster := _caster({&"fire": 3, &"ice": 2})
	var plan := _plan(caster, _SPARK)
	var n := _count(caster, &"fire")
	plan.set_shape(&"fire", n - 1)
	var k := plan.infusion.shape_points
	assert_true(_entry(plan, RIDE, &"fire").value <= n - k, "ride offered at most N - k")
	assert_eq(_entry(plan, RIDE, &"ice").value, _count(caster, &"ice"), "another element: its full count")
	plan.set_shape(&"", 0)
	plan.set_ride(&"fire", n - 1)
	k = plan.infusion.ride_points
	assert_true(_entry(plan, SHAPE, &"fire").value <= n - k, "shape offered at most N - k")
	assert_eq(_entry(plan, RIDE, &"fire").value, n, "a socket's own spend is not held against it")


# ── The click path: socket → MagicMode → InfusionPickMode → the plan ────────

const _PLAYER_FACTION := preload("res://entity/factions/player.tres")


## A real stack: magic armed with lightning_bolt on a caster holding 3 Fire.
func _armed() -> PlayerInputController:
	var world := TestWorld.create(self)
	var node := world.add_node(&"Home", Vector2.ZERO)
	var attacker := TestWorld.new_entity("", null, _PLAYER_FACTION)
	world.graph.add_child(attacker)
	var alloc := TestWorld.around(world.graph).allocator()
	alloc.force_allocate(attacker, node)
	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.start_turn(attacker)
	var bs := BattleSystem.new()
	bs.turn_manager = tm
	bs.allocation_system = alloc
	bs.graph = world.graph
	add_child_autofree(bs)
	var ctl := PlayerInputController.new()
	ctl.graph = world.graph
	ctl.allocation_system = alloc
	ctl.turn_manager = tm
	ctl.battle_system = bs
	ctl.player = attacker
	add_child_autofree(ctl)
	attacker.stat_board.intelligence.base_value = 100.0
	attacker.stat_board.get_stat(ElementRoster.shared().by_id(&"fire").stat.id).base_value = 3.0
	ctl.armed_stack.select_spell(ctl.player, _BOLT)
	ctl.arm_attack(BattleSystem.AttackMode.MAGIC)
	return ctl


func test_a_ride_socket_click_opens_its_chooser_and_picks_step_it() -> void:
	var ctl := _armed()
	var plan := ctl.armed_stack.attack_plan() as MagicAttackPlan
	assert_not_null(plan, "precondition: magic armed")
	var sockets: InfusionSockets = _SOCKETS_SCENE.instantiate()
	add_child_autofree(sockets)
	sockets.bind(plan, ctl.armed_stack)
	var points := plan.infusion.points.duplicate()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	sockets.socket(RIDE)._gui_input(ev)
	var picker := ctl.armed_stack.find(InfusionPickMode) as InfusionPickMode
	assert_not_null(picker, "the ride socket's click opens a chooser")
	assert_eq(picker.socket, RIDE, "on the ride field")
	assert_true(sockets.wheel().visible, "the wheel shows")
	assert_eq(sockets.wheel().entry_count(), ElementRoster.shared().elements.size(), "the roster's elements")
	sockets.wheel().picked.emit(&"fire")
	sockets.wheel().picked.emit(&"fire")
	assert_eq(plan.infusion.ride_element, &"fire", "the ride forged")
	assert_eq(plan.infusion.ride_points, 2, "two picks, two points")
	assert_not_null(ctl.armed_stack.find(InfusionPickMode), "an element pick keeps the chooser open")
	assert_eq(plan.infusion.points, points, "the aspects untouched")


# ── The readout follows an element socket's hover ───────────────────────────

func test_hovering_the_ride_socket_expands_only_the_ride_line() -> void:
	var plan := _plan(_caster({&"fire": 3, &"ice": 2}), _SPARK)
	plan.set_ride(&"fire", 2)
	plan.set_shape(&"ice", 1)
	var readout: CrucibleReadout = preload("res://ui/hud/command_tray/bodies/crucible_readout.tscn").instantiate()
	add_child_autofree(readout)
	readout.bind(plan)
	readout.set_hovered_socket(RIDE)
	var expanded := readout.line_nodes().filter(func(n: CrucibleReadoutLine) -> bool: return n.is_expanded())
	assert_eq(expanded.size(), 1, "one line expands")
	if expanded.size() == 1:
		assert_eq(expanded[0].line().kind, ReadoutLines.Kind.RIDE, "the ride line")
	readout.set_hovered_socket(SHAPE)
	var lit := readout.line_nodes().filter(func(n: CrucibleReadoutLine) -> bool: return n.is_highlighted())
	assert_eq(lit.size(), 1, "one line lights (a shape line has no detail to expand yet)")
	if lit.size() == 1:
		assert_eq(lit[0].line().kind, ReadoutLines.Kind.SHAPE, "the shape line")
	readout.set_hovered_socket(-1)
	assert_false(readout.line_nodes().any(func(n: CrucibleReadoutLine) -> bool: return n.is_expanded()),
			"unhover collapses")
