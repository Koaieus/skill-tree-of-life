class_name TestWorld
extends RefCounted

## A minimal live world for a unit test: a [Graph] from `graph.tscn`, nodes
## and edges added through [method Graph.add_skill_node] / [method Graph.add_edge]
## (so the graph's [Navigator] mirrors them), entities under
## `entities_container`, and an [AllocationSystem] that assigns ownership
## through [method AllocationSystem.force_allocate] — never a bare
## `owned_by =`, which leaves the entity's navigator mirror and SP pool empty.
##
## Composed, not inherited: a fixture holds one and adds its own builders.
## ```
## var w := TestWorld.create(self)
## var a := w.add_node(&"a", Vector2(0, 0))
## var b := w.add_node(&"b", Vector2(100, 0))
## w.link(a, b)
## var red := w.add_entity("Red")
## w.allocate(red, [a])        # a becomes red's core_location
## ```

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _DEFAULT_BOARD := preload("res://entity/default_entity_board.tres")
const ALLOCATOR_NAME := &"TestAllocationSystem"

var test: GutTest
var graph: Graph


## A fresh, empty graph under [param gut], autofreed with the test.
static func create(gut: GutTest, graph_name := "TestGraph") -> TestWorld:
	var w := TestWorld.new()
	w.test = gut
	w.graph = _GRAPH_SCENE.instantiate() as Graph
	w.graph.name = graph_name
	gut.add_child_autofree(w.graph)
	return w


## A world over an existing [param g] — for a helper handed only the graph.
## Its allocator is still the graph's one ([method allocator_for]).
static func around(g: Graph, gut: GutTest = null) -> TestWorld:
	var w := TestWorld.new()
	w.test = gut
	w.graph = g
	return w


## Adds a node named [param id]. [param pos] is a global position, set after
## the node enters the tree; null leaves it at the origin.
func add_node(id: StringName, pos: Variant = null) -> SkillNode:
	var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
	n.name = String(id)
	graph.add_skill_node(n)
	if pos != null:
		n.global_position = pos
	return n


func link(a: SkillNode, b: SkillNode) -> Edge:
	return graph.add_edge(a, b)


## Builds nodes `N0..Nk` from an index-pair [param adjacency] list, linked in
## order; [param positions] maps index -> global position. Returns the nodes
## in index order.
func build(adjacency: Array, positions: Dictionary = {}) -> Array[SkillNode]:
	var count := 0
	for pair in adjacency:
		count = maxi(count, maxi(int(pair[0]), int(pair[1])) + 1)
	var out: Array[SkillNode] = []
	for i in count:
		out.append(add_node(StringName("N%d" % i), positions.get(i)))
	for pair in adjacency:
		link(out[int(pair[0])], out[int(pair[1])])
	return out


## An entity under `entities_container`. [param board] defaults to a deep copy
## of the default entity board; it is assigned before the entity enters the
## tree, because `initialize()` seals it. [param faction] null gives the
## entity its own one-member camp, so two default entities are hostile.
func add_entity(display_name: String, board: EntityStatBoard = null,
		faction: Faction = null, color: Color = Color.WHITE) -> Entity:
	var ent := Entity.new()
	ent.display_name = display_name
	ent.color = color
	if faction == null:
		faction = Faction.new()
		faction.id = StringName("test_camp_%s_%d" % [display_name, ent.get_instance_id()])
		faction.display_name = display_name
	ent.faction = faction
	ent.stat_board = board if board != null \
			else _DEFAULT_BOARD.duplicate(true) as EntityStatBoard
	graph.entities_container.add_child(ent)
	return ent


func allocator() -> AllocationSystem:
	return allocator_for(graph)


## The one [AllocationSystem] of [param g], created on first use and parented
## to it so the graph's teardown takes it too.
static func allocator_for(g: Graph) -> AllocationSystem:
	var existing := g.get_node_or_null(NodePath(String(ALLOCATOR_NAME))) as AllocationSystem
	if existing != null:
		return existing
	var alloc := AllocationSystem.new()
	alloc.name = ALLOCATOR_NAME
	alloc.graph = g
	g.add_child(alloc)
	return alloc


## [method AllocationSystem.force_allocate]s each of [param nodes] to
## [param entity]. The first becomes its `core_location` if it has none.
func allocate(entity: Entity, nodes: Array) -> void:
	var alloc := allocator()
	for n in nodes:
		alloc.force_allocate(entity, n)
	if entity.core_location == null and not nodes.is_empty():
		entity.core_location = nodes[0]
