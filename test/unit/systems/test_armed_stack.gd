extends GutTest
## ArmedStack's push/pop contract, on bare levels with no controller.


class Probe extends ArmedMode:
	var tag: String
	var log: Array
	var present_in_own_pop: bool = true

	func _init(p_tag: String, p_log: Array) -> void:
		tag = p_tag
		log = p_log

	func on_popped() -> void:
		log.append(tag)
		present_in_own_pop = stack != null and self in stack.branch()


var _stack: ArmedStack
var _log: Array
var _root: Probe
var _changes: int


func before_each() -> void:
	_log = []
	_changes = 0
	_stack = ArmedStack.new()
	add_child_autofree(_stack)
	_root = _probe("root")
	_stack.set_root(_root)
	_stack.changed.connect(func() -> void: _changes += 1)


func _probe(tag: String) -> Probe:
	var p := Probe.new(tag, _log)
	return p


func test_pop_top_at_root_returns_false() -> void:
	assert_false(_stack.pop_top(), "the root is unpoppable")
	assert_eq(_stack.branch(), [_root] as Array[ArmedMode])
	assert_eq(_changes, 0, "a refused pop is no operation")


func test_pop_mode_removes_it_and_everything_above_top_down() -> void:
	var a := _probe("a")
	var b := _probe("b")
	var c := _probe("c")
	_stack.push(a)
	_stack.push(b)
	_stack.push(c)
	_changes = 0
	assert_true(_stack.pop(b))
	assert_eq(_stack.branch(), [_root, a] as Array[ArmedMode])
	assert_eq(_log, ["c", "b"], "on_popped runs top-down")
	assert_eq(_changes, 1, "one pop(mode) is one change")


func test_on_popped_runs_after_the_mode_left_the_stack() -> void:
	var a := _probe("a")
	_stack.push(a)
	_stack.pop_top()
	assert_false(a.present_in_own_pop, "a mode is off the branch inside its own on_popped")


func test_switch_to_pops_to_root_then_pushes() -> void:
	var stake := _probe("stake")
	var core_move := _probe("core_move")
	_stack.push(stake)
	_changes = 0
	_stack.switch_to(core_move)
	assert_eq(_stack.branch(), [_root, core_move] as Array[ArmedMode])
	assert_eq(_log, ["stake"])
	assert_eq(_changes, 1, "a switch is one change, not a pop plus a push")


func test_changed_fires_once_per_operation() -> void:
	_stack.push(_probe("a"))
	assert_eq(_changes, 1, "push")
	_stack.push(_probe("b"))
	_stack.push(_probe("c"))
	_changes = 0
	_stack.clear_to_root()
	assert_eq(_changes, 1, "clear_to_root of three levels")
	assert_eq(_stack.branch(), [_root] as Array[ArmedMode])
	_stack.clear_to_root()
	assert_eq(_changes, 1, "clearing an empty stack changes nothing")


func test_top_is_the_last_pushed_and_root_when_empty() -> void:
	assert_eq(_stack.top(), _root)
	var a := _probe("a")
	_stack.push(a)
	assert_eq(_stack.top(), a)


# ── The attack level owns the plan ───────────────────────────────────────────

const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")


func _melee_fixture() -> Dictionary:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var tm: TurnManager = autofree(TurnManager.new())
	add_child(tm)
	var bs: BattleSystem = autofree(BattleSystem.new())
	bs.graph = graph
	bs.turn_manager = tm
	bs.instant_mutation = true
	add_child(bs)
	var player: Entity = autofree(Entity.new())
	player.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.entities_container.add_child(player)
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	var ctl := PlayerInputController.new()
	ctl.graph = graph
	ctl.battle_system = bs
	ctl.turn_manager = tm
	ctl.allocation_system = alloc
	add_child_autofree(ctl)
	ctl.player = player
	tm.start_turn(player)
	return {bs = bs, ctl = ctl, player = player}


func test_pushing_melee_makes_its_plan_the_stacks_and_popping_drops_it() -> void:
	var f := _melee_fixture()
	var ctl: PlayerInputController = f.ctl
	var bs: BattleSystem = f.bs
	var stack := ctl.armed_stack
	var seen: Array = []
	stack.attack_plan_changed.connect(func(p: AttackPlan) -> void: seen.append(p))

	var melee := MeleeMode.new(ctl)
	assert_true(stack.push(melee), "fixture: melee arms on the player's turn")
	var plan := stack.attack_plan()
	assert_true(plan is MeleeAttackPlan, "pushing MeleeMode arms a melee plan")
	assert_eq(plan.attacker, f.player, "the plan is this player's")
	assert_same(bs.attack_plan, plan, "one plan, reachable through BattleSystem too")
	assert_eq(seen.size(), 1, "attack_plan_changed fires once for the push")
	assert_same(seen[0], plan, "it carries the plan itself")

	stack.pop(melee)
	assert_null(stack.attack_plan(), "popping the level drops its plan")
	assert_null(bs.attack_plan, "and BattleSystem's door shows the same nothing")
	assert_eq(seen.size(), 2, "attack_plan_changed fires once for the pop")
	assert_null(seen[1])
