extends GutTest

## [method VisionSystem.sources_for]: the one answer to "which discs of sight
## do these viewers hold" — each owned node at its local `vision_range`, each
## scout row of a viewer's camp at [method ScoutStatus.radius_for], and nothing
## another camp holds.
##
## Layout: A (player camp) owns N0 (x=0) and N1 (x=50); B (npc camp) owns N2
## (x=300); C (camp_3) owns N5 (x=600), which A scouts. The fixture leaves
## `allocation_system` unset and calls `sources_for` directly.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _SCOUTED: ScoutStatus = preload("res://effects/status/scouted.tres")
const _FACTIONS := [preload("res://entity/factions/player.tres"),
		preload("res://entity/factions/npc.tres"), preload("res://entity/factions/camp_3.tres")]

var _graph: Graph
var _alloc: AllocationSystem
var _vision: VisionSystem
var _a: Entity
var _b: Entity
var _c: Entity
var _n0: SkillNode
var _n1: SkillNode
var _n2: SkillNode
var _n5: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_n0 = _spawn("N0", 0.0)
	_n1 = _spawn("N1", 50.0)
	_n2 = _spawn("N2", 300.0)
	_n5 = _spawn("N5", 600.0)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_a = _entity("A", 0)
	_b = _entity("B", 1)
	_c = _entity("C", 2)
	await get_tree().process_frame
	_alloc.force_allocate(_a, _n0)
	_alloc.force_allocate(_a, _n1)
	_alloc.force_allocate(_b, _n2)
	_alloc.force_allocate(_c, _n5)

	_vision = VisionSystem.new()
	_vision.graph = _graph
	_vision.viewers = [_a]
	add_child_autofree(_vision)
	await get_tree().process_frame


func _spawn(nm: String, x: float) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	sn.position = Vector2(x, 0.0)
	_graph.skill_nodes_container.add_child(sn)
	return sn


func _entity(nm: String, faction: int) -> Entity:
	var en: Entity = autofree(Entity.new())
	en.display_name = nm
	en.faction = _FACTIONS[faction]
	en.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(en)
	return en


func _of_kind(sources: Array[VisionSource], kind: VisionSource.Kind) -> Array[VisionSource]:
	var out: Array[VisionSource] = []
	for s in sources:
		if s.kind == kind:
			out.append(s)
	return out


func _nodes(sources: Array[VisionSource]) -> Array:
	var out: Array = []
	for s in sources:
		out.append(s.node)
	return out


func test_owned_nodes_are_owned_sources_at_their_local_vision_range() -> void:
	var owned := _of_kind(_vision.sources_for([_a] as Array[Entity]), VisionSource.Kind.OWNED)
	assert_eq(owned.size(), 2, "A's two owned nodes, nothing else")
	assert_eq(_nodes(owned), [_n0, _n1], "A's nodes, never B's")
	for s in owned:
		assert_eq(s.kind, VisionSource.Kind.OWNED)
		assert_eq(s.center, s.node.global_position, "the disc sits on its node")
		assert_almost_eq(s.radius, float(s.node.get_local_value(&"vision_range")), 0.001,
				"radius is the node's local vision_range")


func test_a_scout_row_is_one_scout_source_for_the_firers_camp_only() -> void:
	_n5.get_combat().apply_status(_SCOUTED, 4.0, _a.faction.id, _a.entity_id)
	var a_sources := _vision.sources_for([_a] as Array[Entity])
	assert_eq(a_sources.size(), 3, "2 OWNED + 1 SCOUT")
	var scout := _of_kind(a_sources, VisionSource.Kind.SCOUT)
	assert_eq(scout.size(), 1, "one scout disc")
	if scout.size() == 1:
		assert_eq(scout[0].node, _n5, "on the scouted node")
		assert_eq(scout[0].center, _n5.global_position)
		assert_almost_eq(scout[0].radius, _SCOUTED.radius_for(_n5, 4), 0.001,
				"the def's radius for the row's stacks")
	var b_sources := _vision.sources_for([_b] as Array[Entity])
	assert_eq(_of_kind(b_sources, VisionSource.Kind.SCOUT).size(), 0, "B holds no scout disc of A's")
	assert_eq(_nodes(b_sources), [_n2], "B's call answers B's own node, none of A's")


func test_no_graph_no_sources() -> void:
	var bare: VisionSystem = autofree(VisionSystem.new())
	assert_eq(bare.sources_for([_a] as Array[Entity]).size(), 0)
