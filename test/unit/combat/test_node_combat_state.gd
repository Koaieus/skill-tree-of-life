extends GutTest

## NodeCombat holds a NodeState (#1141): a shadow's ownership is its clone's
## `owned_by`, resolved through the minting world. Fixture: core(N0) - N1 - N2,
## N1 - N3 — N1 is a cut vertex. N4 is off-territory: `owned_by` written
## directly, so the owner's navigator disagrees and the world orphans it.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _n0: SkillNode
var _n1: SkillNode
var _n2: SkillNode
var _n3: SkillNode
var _n4: SkillNode
var _shadows: Array[EntityCombat] = []
var _worlds: Array[CombatWorld] = []


func before_each() -> void:
	_shadows = []
	_worlds = []
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_n0 = _new_node("N0")
	_n1 = _new_node("N1")
	_n2 = _new_node("N2")
	_n3 = _new_node("N3")
	_n4 = _new_node("N4")
	_add_edge(_n0, _n1)
	_add_edge(_n1, _n2)
	_add_edge(_n1, _n3)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.display_name = "Defender"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)
	await get_tree().process_frame

	for n in [_n0, _n1, _n2, _n3]:
		_alloc.force_allocate(_entity, n)
	_entity.core_location = _n0


func after_each() -> void:
	for s in _shadows:
		s.free_shadow()
	for w in _worlds:
		w.free_shadow()


func _new_node(n: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = n
	_graph.skill_nodes_container.add_child(sn)
	return sn


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)


func test_shadow_strip_nulls_the_clone_owner_and_leaves_the_live_node_owned() -> void:
	var shadow := _entity.get_combat().snapshot()
	_shadows.append(shadow)
	var shadow_n1: NodeCombat = shadow.shadow_for(_n1)
	var shadow_n2: NodeCombat = shadow.shadow_for(_n2)
	assert_eq(shadow_n2._state.owned_by, _entity, "precondition: the clone names the real owner")
	assert_ne(shadow_n2._state, _n2.state, "a shadow holds a clone, never the live state")

	shadow_n1.take_damage(999999.0, null)

	assert_null(shadow_n1._state.owned_by, "the killed node's clone is un-owned")
	assert_null(shadow_n2._state.owned_by, "an islanded node's clone is un-owned")
	assert_false(shadow_n2.is_allocated(), "a stripped clone reads unallocated")
	for n in [_n1, _n2]:
		assert_eq(n.owned_by, _entity, "%s stays owned live" % n.name)
		assert_true(n.get_combat().is_allocated(), "%s's live slice still reads allocated" % n.name)


func test_shadow_owner_resolves_through_its_world() -> void:
	var w := CombatWorld.shadow()
	_worlds.append(w)
	var ns := w.combat_for(_n2)
	assert_not_null(ns, "precondition: the world mints an owned node")
	assert_eq(ns._state.owned_by, _entity, "the clone names the real owner")
	assert_eq(ns.owner(), w.combat_for_entity(_entity), "owner() is the world's slice for that entity")


func test_bare_snapshot_node_owner_is_the_minting_shadow() -> void:
	# A bare snapshot has no world until one is asked for — the first node it
	# mints must still resolve its owner.
	var shadow := _entity.get_combat().snapshot()
	_shadows.append(shadow)
	var ns: NodeCombat = shadow.shadow_for(_n2)
	assert_eq(ns._state.owned_by, _entity, "the clone names the real owner")
	assert_eq(ns.owner(), shadow, "owner() resolves to the minting shadow")


func test_orphan_clone_is_unowned() -> void:
	_n4.owned_by = _entity  # navigator disagrees: the world orphans N4
	var w := CombatWorld.shadow()
	_worlds.append(w)
	var orphan := w.combat_for(_n4)
	assert_not_null(orphan, "precondition: an orphan is minted")
	assert_null(orphan._state.owned_by, "an orphan's clone is un-owned")
	assert_false(orphan.is_allocated(), "an orphan reads unallocated")
	assert_eq(_n4.owned_by, _entity, "the live field is untouched")
	assert_ne(orphan._state, _n4.state, "an orphan holds a clone, never the live state")
