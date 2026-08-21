extends GutTest

## A blade must pass through a co-op partner's territory as cleanly as its own.
## Asserted on [method MeleeAttackPlan.collect_target_excludes] — the physics
## exclude list — rather than through a live swing, because that IS the seam:
## excluded colliders are never queried, so an allied node can't produce a hit
## event at all. Pure method, no physics-server sync timing to fight.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _nodes: Array[SkillNode]
var _attacker: Entity
var _mate: Entity
var _foe: Entity


func _make_entity(ent_name: String, faction: Faction) -> Entity:
	var e := Entity.new()
	e.name = ent_name
	e.display_name = ent_name
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	e.faction = faction
	return e


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	# N0 - N1 (attacker) ... N2 (ally) ... N3 (hostile)
	_nodes = []
	for i in 4:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = _nodes[0]
	e.to = _nodes[1]
	_graph.edges_container.add_child(e)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	var coop := Faction.new()
	coop.id = &"coop_camp"
	var enemy := Faction.new()
	enemy.id = &"enemy_camp"

	_attacker = autofree(_make_entity("Attacker", coop))
	_graph.add_child(_attacker)
	_mate = autofree(_make_entity("Mate", coop))
	_graph.add_child(_mate)
	_foe = autofree(_make_entity("Foe", enemy))
	_graph.add_child(_foe)

	await get_tree().process_frame

	_alloc.force_allocate(_attacker, _nodes[0])
	_attacker.core_location = _nodes[0]
	_alloc.force_allocate(_attacker, _nodes[1])
	_alloc.force_allocate(_mate, _nodes[2])
	_mate.core_location = _nodes[2]
	_alloc.force_allocate(_foe, _nodes[3])
	_foe.core_location = _nodes[3]


func _excludes() -> Array[RID]:
	var plan := MeleeAttackPlan.new()
	plan.attacker = _attacker
	plan.source = _nodes[0]
	var blade: Array[SkillNode] = [_nodes[1]]
	plan.blade_nodes = blade
	return plan.collect_target_excludes()


func test_allied_camp_nodes_are_excluded_from_the_blade_scan() -> void:
	assert_true(_nodes[2].get_rid() in _excludes(),
			"a co-op partner's node must not even be queried by the scan")


func test_own_nodes_are_still_excluded() -> void:
	var out := _excludes()

	assert_true(_nodes[0].get_rid() in out, "the pivot")
	assert_true(_nodes[1].get_rid() in out, "the blade member")


func test_hostile_nodes_are_not_excluded() -> void:
	assert_false(_nodes[3].get_rid() in _excludes(),
			"the whole point of the swing is still hittable")


func test_unallocated_nodes_are_not_excluded() -> void:
	# NEUTRAL is deliberately still scannable — this change is about allies,
	# not about narrowing melee to owned territory.
	_alloc.force_deallocate(_nodes[3])

	assert_false(_nodes[3].get_rid() in _excludes())
