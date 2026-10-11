extends GutTest

## ADR 0055 — a turnless host (a blocker / dormant core: an in-scope entity
## with no initiative pool) ticks its statuses on the WORLD turn — one every N
## played turn ends — never on each turn end, never on an abandoned one.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _BLOCKER_BOARD := preload("res://entity/blocker/blocker_medium_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _blocker: Entity
var _blocker_node: SkillNode
var _world_turns: Array = []


func before_each() -> void:
	_world_turns = []
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_tm = autofree(TurnManager.new())
	_tm.entity_root = _graph
	add_child(_tm)
	_tm.world_turn_ended.connect(func() -> void: _world_turns.append(true))
	for i in 2:
		var p: Entity = autofree(Entity.new())
		p.name = "P%d" % i
		p.display_name = p.name
		p.stat_board = _BOARD.duplicate(true) as EntityStatBoard
		p.stat_board.initiative.current = 0.0
		_graph.entities_container.add_child(p)
	_blocker = autofree(Entity.new())
	_blocker.display_name = "Blocker"
	_blocker.stat_board = _BLOCKER_BOARD.duplicate(true) as EntityStatBoard
	_blocker.entity_tier = 2
	_graph.entities_container.add_child(_blocker)
	_blocker_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(_blocker_node)
	await get_tree().process_frame
	_alloc.force_allocate(_blocker, _blocker_node)
	_blocker.core_location = _blocker_node
	_tm.start_turn(_tm.opening_entity())


## A damage-free poison stand-in: stacks on reapply, one stack decays per tick.
func _poison() -> StatusDef:
	var d := StatusDef.new()
	d.id = &"poison_like"
	d.power_max = 20.0
	d.reapply = StatusDef.Reapply.ACCUMULATE
	d.decay = FlatDecay.new(1.0)
	return d


func _node_power(def: StatusDef) -> float:
	return _blocker_node.get_combat().get_status_power(def.id)


func test_a_blocker_owned_node_ticks_once_per_world_turn() -> void:
	var poison := _poison()
	_blocker_node.get_combat().apply_status(poison, 5.0)
	_tm.end_turn()
	assert_eq(_world_turns.size(), 0, "sanity: 1 of 2 played turn ends")
	assert_eq(_node_power(poison), 5.0, "a played turn end alone does not tick a turnless host")
	_tm.end_turn()
	assert_eq(_world_turns.size(), 1, "sanity: the second played turn end closes the world turn")
	assert_eq(_node_power(poison), 4.0, "the world turn ticks the blocker's node once")


func test_poison_applied_across_your_turns_stacks_before_it_decays() -> void:
	var poison := _poison()
	_blocker_node.get_combat().apply_status(poison, 3.0)
	_tm.end_turn()
	_tm.end_turn()
	assert_eq(_world_turns.size(), 1, "sanity: exactly one world turn in between")
	_blocker_node.get_combat().apply_status(poison, 3.0)
	assert_eq(_node_power(poison), 5.0, "3, one world-turn tick to 2, +3 stacks to 5")


func test_the_blockers_own_statuses_tick_on_the_world_turn() -> void:
	var poison := _poison()
	var host := CombatWorld.live().combat_for_entity(_blocker)
	host.apply_status(poison, 5.0)
	_tm.end_turn()
	assert_eq(host.get_status_power(poison.id), 5.0, "not on a single played turn end")
	_tm.end_turn()
	assert_eq(host.get_status_power(poison.id), 4.0, "once on the world turn")


func test_abandon_turn_never_ticks_a_turnless_host() -> void:
	var poison := _poison()
	_blocker_node.get_combat().apply_status(poison, 5.0)
	_tm.end_turn()
	_tm.abandon_turn(_tm.current_entity)
	assert_eq(_tm.world_turn_progress, 1, "an abandoned turn is not a played turn end")
	assert_eq(_node_power(poison), 5.0, "and ticks no turnless host")
