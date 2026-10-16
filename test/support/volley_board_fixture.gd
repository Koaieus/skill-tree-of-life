class_name VolleyBoardFixture
extends RefCounted

## The shared volley board: an attacker hub [member hub] (200,0) with three
## reaching [member leaves] around a hostile [member target] (450,0), which
## links to a two-node hostile [member cluster] on its far side. Every
## attacker leaf can reach the target (range 1000); nothing links the
## attacker's territory to the target, so the hub (degree 3) never fires.
##
## Firing positions are the attacker's degree-1 nodes, so a node a test adds
## to the attacker with [method add_node] must link at least twice inside the
## territory or it becomes one more shooter — [method assert_firing_positions]
## is the guard (`.claude/rules/ranged-attack-fixtures.md`); [method build]
## runs it on the bare board.

const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

const LEAF_RANGE := 1000.0

var test: GutTest
## The world this board is built on; [member graph] and [member alloc] are its.
var world: TestWorld
var graph: Graph
var alloc: AllocationSystem
var attacker: Entity
var hostile: Entity
var hub: SkillNode
var leaves: Array[SkillNode] = []
var target: SkillNode
var cluster: Array[SkillNode] = []
## Every node by name: `hub`, `leaf_0..2`, `target`, `hostile_a`,
## `hostile_b`, plus whatever [method add_node] adds.
var nodes: Dictionary[StringName, SkillNode] = {}


## Builds the board under [param gut] (autofreed with the test). [param flat]
## gives both entities [method TestBoards.flat_entity_board]; otherwise a deep
## copy of the default entity board.
static func build(gut: GutTest, flat := false) -> VolleyBoardFixture:
	var f := VolleyBoardFixture.new()
	f.test = gut
	f.world = TestWorld.create(gut)
	f.graph = f.world.graph
	f.hub = f._node(&"hub", Vector2(200, 0))
	for i in 3:
		var leaf := f._node(StringName("leaf_%d" % i),
				[Vector2(400, 0), Vector2(450, 150), Vector2(450, -300)][i])
		f.graph.add_edge(leaf, f.hub)
		f.leaves.append(leaf)
	f.target = f._node(&"target", Vector2(450, 0))
	for spec in [[&"hostile_a", Vector2(600, 0)], [&"hostile_b", Vector2(700, 100)]]:
		var n := f._node(spec[0], spec[1])
		f.graph.add_edge(f.target, n)
		f.cluster.append(n)

	f.attacker = f._entity("Attacker", _PLAYER_FACTION, flat)
	f.hostile = f._entity("Hostile", _NPC_FACTION, flat)
	await gut.get_tree().process_frame

	f.alloc = f.world.allocator()
	f.alloc.force_allocate(f.attacker, f.hub)
	for leaf in f.leaves:
		f.alloc.force_allocate(f.attacker, leaf)
	f.attacker.core_location = f.hub
	f.alloc.force_allocate(f.hostile, f.target)
	for n in f.cluster:
		f.alloc.force_allocate(f.hostile, n)
	f.hostile.core_location = f.cluster[0]
	for leaf in f.leaves:
		set_stat(leaf, &"range", LEAF_RANGE)
	await gut.get_tree().process_frame
	f.assert_firing_positions(f.leaves.size())
	return f


## Adds a node named [param id] at [param pos], linked to every node in
## [param links], allocated to [param owner] (null = unallocated).
func add_node(id: StringName, pos: Vector2, owner: Entity = null,
		links: Array[SkillNode] = []) -> SkillNode:
	var n := _node(id, pos)
	for other in links:
		graph.add_edge(n, other)
	if owner != null:
		alloc.force_allocate(owner, n)
	return n


## A local modifier on [param node] — SET by default, so it pins the stat.
static func set_stat(node: SkillNode, id: StringName, value: float,
		op: StatModifier.Operation = StatModifier.Operation.SET) -> void:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = op
	m.value = value
	node.add_local_modifier(m)


## Fails the test unless exactly [param expected] attacker nodes can fire on
## [member target].
func assert_firing_positions(expected: int) -> void:
	var p := RangedAttackPlan.new()
	test.autofree(p)
	p.attacker = attacker
	p.set_target(target)
	test.assert_eq(p.get_reaching_firing_positions().size(), expected,
			"volley board: %d firing positions reach the target" % expected)


func _node(id: StringName, pos: Vector2) -> SkillNode:
	var n := world.add_node(id, pos)
	nodes[id] = n
	return n


func _entity(display: String, faction: Faction, flat: bool) -> Entity:
	return world.add_entity(display, TestBoards.flat_entity_board() if flat else null, faction)
