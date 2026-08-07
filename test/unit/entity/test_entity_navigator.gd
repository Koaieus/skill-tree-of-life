extends GutTest

## #384 pin: territory is strictly per-entity. `EntityNavigator._should_mirror`
## stays `node.owned_by == entity` — allies do NOT bridge subgraphs, even
## though they read ALLIED via `Entity.attitude_to`. Fixtures follow
## .claude/rules/graph.md (populate via add_skill_node/add_edge so the mirror
## actually wires up) and .claude/rules/scene-composition.md.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _ally: Entity


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.display_name = "Mine"
	_entity.faction = _PLAYER_FACTION
	_entity.stat_board = _BOARD.duplicate(true) as StatBoard
	_graph.add_child(_entity)

	_ally = autofree(Entity.new())
	_ally.display_name = "Ally"
	_ally.faction = _PLAYER_FACTION  # same faction → ALLIED, per attitude_to
	_ally.stat_board = _BOARD.duplicate(true) as StatBoard
	_graph.add_child(_ally)

	await get_tree().process_frame  # entity._ready wires navigators


func test_ally_nodes_are_excluded_from_the_entity_mirror() -> void:
	assert_eq(_entity.attitude_to(_ally), Entity.Attitude.ALLIED, "fixture sanity: same faction reads ALLIED")

	var mine := _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.add_skill_node(mine)
	var ally_node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.add_skill_node(ally_node)
	_add_edge(mine, ally_node)

	_alloc.force_allocate(_entity, mine)
	_alloc.force_allocate(_ally, ally_node)

	var mirrored := _entity.navigator.get_mirrored_nodes()
	assert_true(mirrored.has(mine), "the entity's own node is mirrored")
	assert_false(mirrored.has(ally_node),
			"an ally's node stays out of the entity's mirror — territory is per-entity, allies don't bridge subgraphs")


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)
