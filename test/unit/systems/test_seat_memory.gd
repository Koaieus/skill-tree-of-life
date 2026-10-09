extends GutTest
## ArmedStack's per-entity seat memory: every attack mode's last choice is held
## per entity, so a hot-seat handover neither leaks nor loses it.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
## Not the magic plan's bundled fallback (Spark), so "took the pick" is visible.
const _PICK: SpellDef = preload("res://attack/spell/defs/healing_beam.tres")

var _tm: TurnManager
var _ctl: PlayerInputController
var _a: Entity
var _b: Entity


func before_each() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	_tm = autofree(TurnManager.new())
	add_child(_tm)
	var bs: BattleSystem = autofree(BattleSystem.new())
	bs.graph = graph
	bs.turn_manager = _tm
	bs.instant_mutation = true
	add_child(bs)
	_a = _entity(graph)
	_b = _entity(graph)
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	_ctl = PlayerInputController.new()
	_ctl.graph = graph
	_ctl.battle_system = bs
	_ctl.turn_manager = _tm
	_ctl.allocation_system = alloc
	add_child_autofree(_ctl)
	_hand_to(_a)


func _entity(graph: Graph) -> Entity:
	var e: Entity = autofree(Entity.new())
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.entities_container.add_child(e)
	return e


func _hand_to(entity: Entity) -> void:
	_ctl.clear_transient_state()
	_ctl.player = entity
	# end_turn may tick the clock straight into the next ready entity's turn.
	for _i in 4:
		if _tm.current_entity == null or _tm.current_entity == entity:
			break
		_tm.end_turn()
	if _tm.current_entity == null:
		_tm.start_turn(entity)


func _armed(mode: BattleSystem.AttackMode) -> AttackPlan:
	assert_true(_ctl.arm_attack(mode), "fixture: mode %d arms" % mode)
	return _ctl.armed_stack.attack_plan()


func test_hot_seat_keeps_each_entitys_spell_swing_and_infusion() -> void:
	var stack := _ctl.armed_stack
	stack.select_spell(_a, _PICK)
	stack.memory_for(_a).melee.next_swing_cw = true
	stack.memory_for(_a).magic.last_infusion[_PICK.id] = {&"fire": 1}

	_hand_to(_b)
	var b_mem := stack.memory_for(_b)
	assert_null(b_mem.magic.selected_spell, "B starts with no picked spell")
	assert_false(b_mem.melee.next_swing_cw, "B swings ccw by default")
	assert_true(b_mem.magic.last_infusion.is_empty(), "B has no infusion memory")
	assert_ne((_armed(BattleSystem.AttackMode.MAGIC) as MagicAttackPlan).spell, _PICK,
			"B's magic plan does not take A's spell")
	assert_false((_armed(BattleSystem.AttackMode.MELEE) as MeleeAttackPlan).swing_cw,
			"B's melee plan does not take A's swing")

	_hand_to(_a)
	var a_mem := stack.memory_for(_a)
	assert_eq(a_mem.magic.selected_spell, _PICK, "A's spell is back")
	assert_true(a_mem.melee.next_swing_cw, "A's swing is back")
	assert_eq(a_mem.magic.last_infusion.get(_PICK.id, {}), {&"fire": 1},
			"A's infusion is back")
	assert_eq((_armed(BattleSystem.AttackMode.MAGIC) as MagicAttackPlan).spell, _PICK,
			"A's magic plan is minted with A's spell")
	assert_true((_armed(BattleSystem.AttackMode.MELEE) as MeleeAttackPlan).swing_cw,
			"A's melee plan is minted with A's swing")


func test_memory_outlives_clear_transient_state() -> void:
	var stack := _ctl.armed_stack
	stack.select_spell(_a, _PICK)
	_ctl.clear_transient_state()
	assert_eq(stack.memory_for(_a).magic.selected_spell, _PICK)


func test_select_spell_for_another_entity_leaves_the_armed_plan_alone() -> void:
	var plan := _armed(BattleSystem.AttackMode.MAGIC) as MagicAttackPlan
	var before := plan.spell
	_ctl.armed_stack.select_spell(_b, _PICK)
	assert_eq(plan.spell, before, "A's armed plan is not re-equipped by B's pick")
