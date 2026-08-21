extends GutTest

## EntityCombat.snapshot() (#498 step 2 — see docs/domain/attack-timeline.md).
## Fixture: core(N0) - N1 - N2, N1 - N3, so N1 is a cut vertex — removing it
## islands {N2, N3} from the core. Same shape test_entity_death.gd uses.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _n0: SkillNode  # core
var _n1: SkillNode  # cut vertex
var _n2: SkillNode
var _n3: SkillNode
var _events_fired: int = 0
var _shadows: Array[EntityCombat] = []


func before_each() -> void:
	_events_fired = 0
	_shadows = []

	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_n0 = _new_node("N0")
	_n1 = _new_node("N1")
	_n2 = _new_node("N2")
	_n3 = _new_node("N3")
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
	await get_tree().process_frame  # entity._ready: navigator wiring

	for n in [_n0, _n1, _n2, _n3]:
		_alloc.force_allocate(_entity, n)
	_entity.core_location = _n0

	for s in [Events.skill_node_damaged, Events.skill_node_healed, Events.skill_node_depleted,
			Events.entity_dying, Events.entity_died, Events.entity_death_shown]:
		s.connect(_count_event)


func after_each() -> void:
	for s in [Events.skill_node_damaged, Events.skill_node_healed, Events.skill_node_depleted,
			Events.entity_dying, Events.entity_died, Events.entity_death_shown]:
		if s.is_connected(_count_event):
			s.disconnect(_count_event)
	for s in _shadows:
		s.free_shadow()


func _count_event(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	_events_fired += 1


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


func _owned_count() -> int:
	var c := 0
	for n in [_n0, _n1, _n2, _n3]:
		if n.owned_by == _entity:
			c += 1
	return c


# ── Host invariant ───────────────────────────────────────────────────────────

func test_snapshot_host_is_null() -> void:
	var shadow := _entity.get_combat().snapshot()
	_shadows.append(shadow)
	assert_null(shadow.host, "a snapshot must be a hostless shadow")
	for n in shadow.owned():
		assert_null(n.host, "every snapshotted NodeCombat must also be hostless")


func test_simulated_kill_emits_nothing_on_events() -> void:
	var shadow := _entity.get_combat().snapshot()
	_shadows.append(shadow)
	var shadow_n1: NodeCombat = shadow._shadow_by_real[_n1]
	shadow_n1.take_damage(999999.0, null)
	assert_eq(_events_fired, 0, "a shadow kill must never reach the Events bus")
	# And the real world is untouched.
	assert_eq(_n1.owned_by, _entity, "the real node must still be owned")
	assert_eq(_owned_count(), 4, "the real territory must be unaffected by a shadow kill")


# ── Never cache owner/board (live) ──────────────────────────────────────────

func test_live_slice_never_caches_ownership() -> void:
	var combat := _n1.get_combat()
	assert_true(combat.is_allocated(), "precondition: N1 starts owned")
	# AllocationSystem writes owned_by directly — the slice has no idea this
	# happened, and must still read it correctly on the very next call.
	_alloc.force_deallocate(_n1)
	assert_false(combat.is_allocated(), "the slice must read the deallocation with nobody telling it")


# ── Islanding parity ─────────────────────────────────────────────────────────

func test_shadow_kill_islands_the_same_set_as_the_live_navigator() -> void:
	var ground_truth: Array[SkillNode] = _entity.navigator.nodes_islanded_by_removing(_n1, _n0)
	assert_eq(ground_truth.size(), 2, "precondition: removing the cut vertex islands N2 + N3")

	var shadow := _entity.get_combat().snapshot()
	_shadows.append(shadow)
	var shadow_n1: NodeCombat = shadow._shadow_by_real[_n1]
	shadow_n1.take_damage(999999.0, null)

	var still_owned := shadow.owned()
	assert_false(still_owned.has(shadow_n1), "the killed node itself must be stripped")
	for real in ground_truth:
		var shadow_equiv: NodeCombat = shadow._shadow_by_real[real]
		assert_false(still_owned.has(shadow_equiv),
				"%s must be islanded on the shadow exactly as it is live" % real.name)
	assert_true(still_owned.has(shadow._shadow_by_real[_n0]), "the core survives — only N1's arm islands")

	# The live world never moved.
	assert_eq(_owned_count(), 4, "a shadow-resolved kill must not touch real ownership")


# ── Recursive entity-death strip ────────────────────────────────────────────

func test_core_overflow_on_shadow_strips_every_owned_node() -> void:
	var shadow := _entity.get_combat().snapshot()
	_shadows.append(shadow)
	(shadow.board().get_stat(&"health") as PoolStat).set_current(1.0)
	var shadow_core: NodeCombat = shadow._shadow_by_real[_n0]
	shadow_core.take_damage(999999.0, null)

	assert_true(shadow.owned().is_empty(), "chipping health to 0 must strip the whole shadow territory")
	# Real entity is completely untouched.
	assert_eq(_owned_count(), 4, "the real entity must still own everything")
	assert_false(_entity.is_dead, "the real entity must not have died")
	assert_eq(_events_fired, 0, "no Events traffic for a shadow's simulated death")
