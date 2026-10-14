extends GutTest

## The magic tray's infusion sockets: one per `infusion_slots` the caster owns
## plus one ghost for the next INT tier; a filled socket reads its exchange
## line; left-click opens the [AspectWheel] through [InfusionPickMode] and every
## close path comes from the stack; the seat remembers the infusion per spell.
##
## Board for the stack tests: Pivot - Joint - Tip owned by the attacker;
## Hostile adjacent to Tip, Far adjacent to Hostile, both owned by an NPC.

const _VENOM: SpellDef = preload("res://attack/spell/defs/venom_burst.tres")
const _SPARK: SpellDef = preload("res://attack/spell/defs/spark.tres")
const _SOCKETS_SCENE := preload("res://ui/hud/command_tray/bodies/infusion_sockets.tscn")
const _READOUT_SCENE := preload("res://ui/hud/command_tray/bodies/crucible_readout.tscn")
const _BODY_SCENE := preload("res://ui/hud/command_tray/bodies/magic_body.tscn")
const _POISON_STATUS: StatusDef = preload("res://effects/status/poison.tres")
const _STUB_ARM := preload("res://test/fixtures/stub_arm.gd")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

var h: SpellTestHelper


func before_each() -> void:
	h = SpellTestHelper.new()


## Every aspect zeroed but poison, which holds [param poison]; INT [param intelligence].
func _caster(poison: float, intelligence: float = 100.0) -> Entity:
	var graph := h.make_graph([[0, 1]], self)
	var atk := h.make_entity(graph, "ATK", Color.RED)
	var board := atk.stat_board
	board.intelligence.base_value = intelligence
	for aspect in AspectRoster.shared().aspects:
		if aspect.stat != null and board.get_stat(aspect.stat.id) != null:
			board.get_stat(aspect.stat.id).base_value = 0.0
	board.facet(&"poison", StatDef.Role.ASPECT).base_value = poison
	return atk


func _plan(caster: Entity, spell: SpellDef = _VENOM) -> MagicAttackPlan:
	var plan := MagicAttackPlan.new()
	plan.attacker = caster
	plan.set_spell(spell)
	return plan


func _sockets(plan: MagicAttackPlan, stack: ArmedStack = null) -> InfusionSockets:
	var sockets: InfusionSockets = _SOCKETS_SCENE.instantiate()
	add_child_autofree(sockets)
	sockets.bind(plan, stack)
	return sockets


func _click(socket: InfusionSocket, button: MouseButton) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	socket._gui_input(ev)


# ── The ladder ───────────────────────────────────────────────────────────────

func test_int_ladder_owned_sockets_and_one_ghost() -> void:
	var cases := [[5.0, 0, "INT 10"], [10.0, 1, "INT 100"], [100.0, 2, "INT 1000"],
			[1000.0, 3, ""]]
	for c in cases:
		var plan := _plan(_caster(2.0, c[0]))
		var sockets := _sockets(plan)
		assert_eq(sockets.socket_count(), c[1], "INT %d: owned sockets" % c[0])
		assert_eq(sockets.ghost_text(), c[2], "INT %d: the ghost" % c[0])
		if c[1] > 0:
			assert_eq(sockets.socket(0).state, InfusionSocket.State.EMPTY, "an owned socket starts empty")
		if not (c[2] as String).is_empty():
			assert_eq(sockets.socket(c[1]).state, InfusionSocket.State.LOCKED, "the ghost is last")


func test_a_filled_socket_reads_its_exchange_line_and_right_click_clears_it() -> void:
	var plan := _plan(_caster(40.0))
	var sockets := _sockets(plan)
	plan.set_socket(0, &"poison")
	var socket := sockets.socket(0)
	assert_eq(socket.state, InfusionSocket.State.FILLED)
	assert_eq(socket.line_text(), InfusionExchange.line(_VENOM, &"poison", 40))
	_click(socket, MOUSE_BUTTON_RIGHT)
	assert_true(plan.infusion.points.is_empty(), "right-click empties the socket")
	assert_eq(sockets.socket(0).state, InfusionSocket.State.EMPTY)
	assert_eq(plan.aspect_overrun(), 0)


func test_the_magic_body_hosts_the_sockets() -> void:
	var body: MagicBody = _BODY_SCENE.instantiate()
	add_child_autofree(body)
	assert_not_null(body.get_node_or_null("%InfusionSockets") as InfusionSockets)


# ── Carried over from the stepper row ────────────────────────────────────────

func test_the_readout_reads_the_infused_intake() -> void:
	var caster := _caster(2.0)
	var plan := _plan(caster)
	_sockets(plan)
	var readout: CrucibleReadout = _READOUT_SCENE.instantiate()
	add_child_autofree(readout)
	readout.bind(plan)
	plan.set_socket(0, &"poison")
	# venom burst: innate + floor(2 points × affinity), through the landing's fold.
	var aff: AspectIntake = _VENOM.intakes[0]
	var stacks := _POISON_STATUS.stacks_per_hit(caster.stat_board, aff.innate + floorf(2.0 * aff.affinity_gain / aff.affinity_cost))
	var nodes := readout.line_nodes()
	assert_eq(nodes.size(), 1, "venom lands poison, so one line shows")
	if nodes.size() == 1:
		assert_eq(nodes[0].line().per_hit, stacks)


## Socket 0 sits at the arc's right end, so the crucible's traces nest.
func test_socket_zero_sits_rightmost() -> void:
	var sockets := _sockets(_plan(_caster(2.0, 10000.0)))
	assert_gt(sockets.socket_count(), 1, "guard: two sockets or more")
	for i in range(1, sockets.socket_count() + 1):
		var s := sockets.socket(i)
		if s != null:
			assert_lt(s.position.x, sockets.socket(i - 1).position.x, "socket %d left of socket %d" % [i, i - 1])


func test_the_seat_remembers_the_infusion_per_spell_clamped_to_todays_caps() -> void:
	var caster := _caster(2.0)
	var plan := _plan(caster)
	var stack: ArmedStack = _STUB_ARM.stack_holding(plan)
	autofree(stack)
	stack.select_spell(plan.attacker, _VENOM)
	plan.set_infusion(&"poison", 2)
	stack.select_spell(plan.attacker, _SPARK)
	assert_eq(plan.infusion.points.get(&"poison", 0), 0, "another spell starts from its own memory")
	stack.select_spell(plan.attacker, _VENOM)
	assert_eq(plan.infusion.points.get(&"poison", 0), 2, "back to venom restores its infusion")
	stack.select_spell(plan.attacker, _SPARK)
	caster.stat_board.facet(&"poison", StatDef.Role.ASPECT).base_value = 1.0
	stack.select_spell(plan.attacker, _VENOM)
	assert_eq(plan.infusion.points.get(&"poison", 0), 1, "restored, clamped to today's aspect")
	assert_eq(plan.aspect_overrun(), 0)


func test_a_fresh_plan_with_the_sticky_spell_gets_its_memory() -> void:
	var caster := _caster(2.0)
	var first := _plan(caster)
	var stack: ArmedStack = _STUB_ARM.stack_holding(first)
	autofree(stack)
	stack.select_spell(first.attacker, _VENOM)
	first.set_infusion(&"poison", 2)
	stack.cancel_attack()
	var second := _plan(caster)
	stack.push(_STUB_ARM.new(second))
	assert_eq(second.infusion.points.get(&"poison", 0), 2, "a repeat cast needs no clicks")


# ── The wheel on a live stack ────────────────────────────────────────────────

var _graph: Graph
var _bs: BattleSystem
var _ctl: PlayerInputController
var _attacker: Entity
var _enemy: SkillNode


func _spawn(nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	sn.position = pos
	_graph.add_skill_node(sn)
	return sn


func _entity(faction: Faction) -> Entity:
	var e: Entity = autofree(Entity.new())
	e.faction = faction
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(e)
	return e


func _live() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	var pivot := _spawn("Pivot", Vector2(0, 0))
	var joint := _spawn("Joint", Vector2(200, 0))
	var tip := _spawn("Tip", Vector2(400, 0))
	_enemy = _spawn("Hostile", Vector2(450, 0))
	var far := _spawn("Far", Vector2(600, 0))
	_graph.add_edge(pivot, joint)
	_graph.add_edge(joint, tip)
	_graph.add_edge(tip, _enemy)
	_graph.add_edge(_enemy, far)
	_attacker = _entity(_PLAYER_FACTION)
	var hostile := _entity(_NPC_FACTION)
	var alloc := AllocationSystem.new()
	alloc.graph = _graph
	add_child_autofree(alloc)
	for n in [pivot, joint, tip]:
		alloc.force_allocate(_attacker, n)
	alloc.force_allocate(hostile, _enemy)
	alloc.force_allocate(hostile, far)
	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.start_turn(_attacker)
	_bs = BattleSystem.new()
	_bs.turn_manager = tm
	_bs.allocation_system = alloc
	_bs.graph = _graph
	_bs.instant_mutation = true
	add_child_autofree(_bs)
	_ctl = PlayerInputController.new()
	_ctl.graph = _graph
	_ctl.allocation_system = alloc
	_ctl.turn_manager = tm
	_ctl.battle_system = _bs
	_ctl.player = _attacker
	add_child_autofree(_ctl)
	var board := _attacker.stat_board
	board.intelligence.base_value = 10000.0
	board.facet(&"poison", StatDef.Role.ASPECT).base_value = 5.0
	board.facet(&"curse", StatDef.Role.ASPECT).base_value = 3.0
	_ctl.armed_stack.select_spell(_ctl.player, SpellCatalog.SPARK)
	_ctl.arm_attack(BattleSystem.AttackMode.MAGIC)
	assert_not_null(_stack().find(MagicMode), "precondition: magic armed")


func _stack() -> ArmedStack:
	return _ctl.armed_stack


func _magic() -> MagicAttackPlan:
	return _stack().attack_plan() as MagicAttackPlan


func _chooser() -> InfusionPickMode:
	return _stack().find(InfusionPickMode) as InfusionPickMode


## The chooser is gone and only it: the magic level below survived (no double pop).
func _assert_closed_alone(why: String) -> void:
	assert_null(_chooser(), "%s: the chooser closed" % why)
	assert_not_null(_stack().find(MagicMode), "%s: the magic level survived" % why)


func test_clicking_a_socket_opens_the_wheel_and_every_close_path_closes_it() -> void:
	_live()
	var sockets := _sockets(_magic(), _stack())
	assert_false(sockets.wheel().visible, "closed at rest")
	_click(sockets.socket(1), MOUSE_BUTTON_LEFT)
	assert_not_null(_chooser(), "left-click opens the chooser")
	assert_eq(_chooser().socket, 1)
	assert_true(sockets.wheel().visible, "the wheel follows the stack")
	assert_eq(sockets.wheel().entry_count(), InfusionChoices.entries(_magic(), 1).size())
	assert_gt(sockets.wheel().entry_count(), 0, "guard: the caster holds aspects")
	_click(sockets.socket(1), MOUSE_BUTTON_LEFT)
	assert_null(_chooser(), "clicking the open socket again closes it")
	assert_false(sockets.wheel().visible)

	_click(sockets.socket(0), MOUSE_BUTTON_LEFT)
	_stack().pop_top()
	_assert_closed_alone("Esc")
	assert_false(sockets.wheel().visible)

	_click(sockets.socket(0), MOUSE_BUTTON_LEFT)
	sockets.wheel().dismissed.emit()
	_assert_closed_alone("the wheel's right-click")
	assert_false(sockets.wheel().visible)
	assert_true(_magic().infusion.points.is_empty(), "no close path wrote the plan")

	_click(sockets.socket(0), MOUSE_BUTTON_LEFT)
	sockets.wheel().picked.emit(&"poison")
	_assert_closed_alone("a pick")
	assert_false(sockets.wheel().visible)
	assert_eq(_magic().infusion.points.get(&"poison", 0), 5, "the pick socketed held poison")
	assert_eq(sockets.socket(0).state, InfusionSocket.State.FILLED)


func test_a_launch_closes_the_wheel_without_changing_the_plan() -> void:
	_live()
	var plan := _magic()
	var sockets := _sockets(plan, _stack())
	assert_true(_stack().find(MagicMode).set_target(_enemy), "precondition")
	_click(sockets.socket(0), MOUSE_BUTTON_LEFT)
	assert_true(sockets.wheel().visible, "precondition: open")
	assert_true(plan.is_valid(), "precondition: %s" % str(plan.validate()))
	await _bs.launch_attack(plan)
	await get_tree().process_frame
	assert_null(_chooser(), "the launch popped the chooser")
	assert_false(sockets.wheel().visible, "and the wheel followed")
	assert_true(plan.infusion.points.is_empty(), "plan untouched")


func test_the_spell_picker_and_the_aspect_chooser_exclude_each_other() -> void:
	_live()
	var magic := _stack().find(MagicMode) as MagicMode
	assert_true(magic.toggle_picker(), "precondition: spell picker open")
	assert_true(magic.toggle_socket(0))
	assert_null(_stack().find(SpellPickMode), "opening a socket closes the spell picker")
	assert_eq(_chooser().socket, 0)
	assert_true(magic.toggle_picker())
	assert_null(_chooser(), "opening the spell picker closes the chooser")
	assert_not_null(_stack().find(SpellPickMode))
	assert_not_null(_stack().find(MagicMode))
