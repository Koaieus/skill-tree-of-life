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
const _HEALING_BEAM: SpellDef = preload("res://attack/spell/defs/healing_beam.tres")


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
	var stack := ctl.armed_stack
	var seen: Array = []
	stack.attack_plan_changed.connect(func(p: AttackPlan) -> void: seen.append(p))

	var melee := MeleeMode.new(ctl)
	assert_true(stack.push(melee), "fixture: melee arms on the player's turn")
	var plan := stack.attack_plan()
	assert_true(plan is MeleeAttackPlan, "pushing MeleeMode arms a melee plan")
	assert_eq(plan.attacker, f.player, "the plan is this player's")
	assert_eq(seen.size(), 1, "attack_plan_changed fires once for the push")
	assert_same(seen[0], plan, "it carries the plan itself")

	stack.pop(melee)
	assert_null(stack.attack_plan(), "popping the level drops its plan")
	assert_eq(seen.size(), 2, "attack_plan_changed fires once for the pop")
	assert_null(seen[1])


func test_each_attack_level_arms_its_own_mode_plan_for_this_player() -> void:
	var cases := {
		BattleSystem.AttackMode.MELEE: MeleeAttackPlan,
		BattleSystem.AttackMode.RANGED: RangedAttackPlan,
		BattleSystem.AttackMode.MAGIC: MagicAttackPlan,
	}
	var f := _melee_fixture()
	var ctl: PlayerInputController = f.ctl
	for mode in cases:
		assert_true(ctl.arm_attack(mode), "mode %d arms" % mode)
		var plan := ctl.armed_stack.attack_plan()
		assert_eq(plan.get_script(), cases[mode])
		assert_eq(plan.mode, mode)
		assert_eq(plan.attacker, f.player, "the plan's attacker is the turn's entity")
	ctl.arm_attack(BattleSystem.AttackMode.NONE)
	assert_null(ctl.armed_stack.attack_plan(), "NONE pops the attack level and its plan")


# ── What the seat keeps besides the plan ─────────────────────────────────────

func test_next_melee_cw_is_sticky_across_reset_and_a_fresh_arm() -> void:
	var f := _melee_fixture()
	var ctl: PlayerInputController = f.ctl
	var stack := ctl.armed_stack
	stack.next_melee_cw = true
	ctl.arm_attack(BattleSystem.AttackMode.MELEE)
	var plan := stack.attack_plan() as MeleeAttackPlan
	assert_true(plan.swing_cw, "the new melee plan takes the sticky direction")
	stack.reset_plan()
	assert_same(stack.attack_plan(), plan, "reset_plan keeps the plan itself")
	assert_true(stack.next_melee_cw, "reset_plan keeps the sticky direction")
	stack.cancel_attack()
	ctl.arm_attack(BattleSystem.AttackMode.MELEE)
	assert_true((stack.attack_plan() as MeleeAttackPlan).swing_cw,
			"a fresh melee plan still takes it")


func test_selected_spell_is_sticky_and_re_equips_the_armed_plan() -> void:
	var f := _melee_fixture()
	var ctl: PlayerInputController = f.ctl
	var stack := ctl.armed_stack
	watch_signals(stack)
	stack.selected_spell = SpellCatalog.SPARK
	assert_signal_emitted(stack, "selected_spell_changed")
	ctl.arm_attack(BattleSystem.AttackMode.MAGIC)
	assert_eq((stack.attack_plan() as MagicAttackPlan).spell, SpellCatalog.SPARK,
			"the new magic plan takes the sticky spell")
	stack.reset_plan()
	assert_eq(stack.selected_spell, SpellCatalog.SPARK, "reset_plan keeps the spell")
	assert_eq((stack.attack_plan() as MagicAttackPlan).spell, SpellCatalog.SPARK)
	stack.selected_spell = _HEALING_BEAM
	assert_eq((stack.attack_plan() as MagicAttackPlan).spell, _HEALING_BEAM,
			"picking a spell re-equips the armed magic plan")


func test_an_attack_level_refuses_to_push_mid_swing() -> void:
	var f := _melee_fixture()
	var ctl: PlayerInputController = f.ctl
	var bs: BattleSystem = f.bs
	bs.is_launching = true
	assert_false(ctl.arm_attack(BattleSystem.AttackMode.MELEE), "no arm while launching")
	assert_null(ctl.armed_stack.attack_plan())
