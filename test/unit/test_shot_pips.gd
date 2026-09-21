extends GutTest

## #959 (C8): the per-leaf shots-left pip row. A leaf shows `shots_left()` lit
## pips of `max_shots_per_leaf` while the LOCAL attacker's plan is RANGED and
## the node is one of that attacker's leaves; hidden otherwise. Refreshed off
## `shots_fired_this_turn` writes (mark_shot_fired, the firer's turn-end
## reset) and off BattleSystem's plan signals — never per frame.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _battle: BattleSystem
var _attacker: Entity
var _leaf: SkillNode
var _other: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_leaf = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_other = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.add_skill_node(_leaf)
	_graph.add_skill_node(_other)
	_graph.add_edge(_leaf, _other)

	_attacker = autofree(Entity.new())
	_attacker.faction = _PLAYER_FACTION
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_attacker)
	await get_tree().process_frame

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_alloc.force_allocate(_attacker, _leaf)
	_alloc.force_allocate(_attacker, _other)

	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.start_turn(_attacker)

	_battle = BattleSystem.new()
	_battle.turn_manager = tm
	_battle.allocation_system = _alloc
	_battle.graph = _graph
	add_child_autofree(_battle)

	# The node discovers BattleSystem the way PlayerInputController does — via
	# the HighlightController group — so one must be in the tree.
	var ctl := HighlightController.new()
	ctl.battle_system = _battle
	add_child_autofree(ctl)


func _pips(n: SkillNode) -> Node:
	return n.shot_pips


func test_ranged_leaf_shows_shots_left_of_max() -> void:
	_battle.request_attack_mode(BattleSystem.AttackMode.RANGED)
	_leaf.mark_shot_fired(2)
	var p := _pips(_leaf)
	assert_true(p.visible, "ranged + my leaf: pips shown")
	assert_eq(p.lit, 3, "shots_left() == 5 - 2")
	assert_eq(p.total, 5, "max_shots_per_leaf at level 1")


func test_melee_mode_hides_pips() -> void:
	_battle.request_attack_mode(BattleSystem.AttackMode.RANGED)
	_leaf.mark_shot_fired(2)
	_battle.request_attack_mode(BattleSystem.AttackMode.MELEE)
	assert_false(_pips(_leaf).visible, "melee: no pips")


func test_no_plan_hides_pips() -> void:
	_leaf.mark_shot_fired(1)
	assert_false(_pips(_leaf).visible, "no attack plan armed: no pips")


func test_firer_turn_end_reset_relights_all() -> void:
	_battle.request_attack_mode(BattleSystem.AttackMode.RANGED)
	_leaf.mark_shot_fired(5)
	assert_eq(_pips(_leaf).lit, 0, "fixture: spent")
	# The exact write Entity._on_turn_ended performs over its fired set.
	_leaf.shots_fired_this_turn = 0
	assert_eq(_pips(_leaf).lit, 5, "turn-end reset relights every pip")
	assert_true(_pips(_leaf).visible)


func test_non_leaf_hides_pips() -> void:
	var third := _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.add_skill_node(third)
	_graph.add_edge(_leaf, third)
	_alloc.force_allocate(_attacker, third)
	_battle.request_attack_mode(BattleSystem.AttackMode.RANGED)
	assert_false(_pips(_leaf).visible, "degree 2 inside my territory: not a leaf")
	assert_true(_pips(third).visible, "the new degree-1 node is")


func test_other_entitys_leaf_hides_pips() -> void:
	var foe: Entity = autofree(Entity.new())
	foe.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(foe)
	await get_tree().process_frame
	var theirs := _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.add_skill_node(theirs)
	_alloc.force_allocate(foe, theirs)
	_battle.request_attack_mode(BattleSystem.AttackMode.RANGED)
	assert_false(_pips(theirs).visible, "not the attacker's node")
