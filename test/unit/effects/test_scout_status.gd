extends GutTest

## [ScoutStatus] — the scout node status: camp-keyed, LINGER, flat decay, and
## its disc radius derived from the count, `radius_scale · √n · V`, where V is
## the node's live local `vision_range` while owned, else the sight it had
## when it last lost its owner, else `fallback_radius_factor × radius`.
## Asserts ratios and invariants against the def's own knobs, never their
## authored values.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SCOUT_PATH := "res://effects/status/scouted.tres"

var _graph: Graph
var _alloc: AllocationSystem
var _a: Entity


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_a = autofree(Entity.new())
	_a.name = "A"
	_a.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(_a)
	await get_tree().process_frame


func _def() -> ScoutStatus:
	var d := load(_SCOUT_PATH) as ScoutStatus
	assert_not_null(d, "scouted.tres is a ScoutStatus")
	return d


func _new_node() -> SkillNode:
	var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(n)
	await get_tree().process_frame
	return n


func _add_vision(node: SkillNode, amount: float) -> void:
	var m := StatModifier.new()
	m.stat_id = &"vision_range"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = amount
	node.add_local_modifier(m)


## An owned node whose live local sight is strictly positive.
func _owned_node() -> SkillNode:
	var n: SkillNode = await _new_node()
	_alloc.force_allocate(_a, n)
	_add_vision(n, 300.0)
	return n


func _row(node: SkillNode, id: StringName, key: Variant) -> NodeStatus:
	for r in node.get_combat().get_statuses():
		if r.def.id == id and r.key == key:
			return r
	return null


# (a) owned: the live sight, and √n in the count
func test_owned_radius_is_scale_sqrt_n_live_vision() -> void:
	var d := _def()
	if d == null:
		return
	var n: SkillNode = await _owned_node()
	var v_live := float(n.get_local_value(&"vision_range"))
	assert_gt(v_live, 0.0, "the owned node sees")
	var r1 := d.radius_for(n, 1)
	assert_almost_eq(r1, d.radius_scale * v_live, 0.001, "one stack is scale · V_live")
	assert_almost_eq(d.radius_for(n, 4), 2.0 * r1, 0.001, "4 stacks = 2 × 1 stack")
	assert_almost_eq(d.radius_for(n, 9), 3.0 * r1, 0.001, "9 stacks = 3 × 1 stack")
	assert_eq(d.radius_for(n, 0), 0.0, "no stacks, no disc")


# (b) deallocated: the sight it had while owned, whatever the board does next
func test_deallocated_node_remembers_its_owned_sight() -> void:
	var d := _def()
	if d == null:
		return
	var n: SkillNode = await _owned_node()
	var r_owned := d.radius_for(n, 4)
	var v_live := float(n.get_local_value(&"vision_range"))
	_alloc.force_deallocate(n)
	assert_null(n.owned_by, "unowned")
	assert_almost_eq(n.last_owned_vision, v_live, 0.001, "the sight was sampled on dealloc")
	assert_almost_eq(d.radius_for(n, 4), r_owned, 0.001, "the remembered sight drives the disc")
	_add_vision(n, 500.0)
	assert_almost_eq(d.radius_for(n, 4), r_owned, 0.001, "a board change after dealloc does not move it")


# (c) never owned: the fallback, a multiple of the node's own radius
func test_never_owned_node_uses_the_radius_fallback() -> void:
	var d := _def()
	if d == null:
		return
	var n: SkillNode = await _new_node()
	assert_eq(n.last_owned_vision, 0.0, "never owned remembers nothing")
	assert_almost_eq(d.radius_for(n, 1),
			d.radius_scale * d.fallback_radius_factor * n.radius, 0.001,
			"V = fallback_radius_factor × radius")
	assert_almost_eq(d.radius_for(n, 4), 2.0 * d.radius_for(n, 1), 0.001, "still √n")


# (d) camp-keyed accumulation, own-camp visibility
func test_camps_accumulate_apart_and_see_only_their_own() -> void:
	var d := _def()
	if d == null:
		return
	var n: SkillNode = await _owned_node()
	n.get_combat().apply_status(d, 1.0, &"A", 1)
	n.get_combat().apply_status(d, 1.0, &"A", 1)
	n.get_combat().apply_status(d, 1.0, &"B", 2)
	var a := _row(n, d.id, &"A")
	var b := _row(n, d.id, &"B")
	assert_not_null(a, "camp A has its row")
	assert_not_null(b, "camp B has its row")
	if a == null or b == null:
		return
	assert_eq(a.power, 2.0, "same-camp scouts stack")
	assert_eq(b.power, 1.0, "another camp's scout files its own row")
	assert_false(d.count_visible(a, &"B", 2), "camp B cannot read camp A's count")
	assert_true(d.count_visible(a, &"A", 1), "camp A reads its own count")


# (e) lingers through dealloc, one stack per tick
func test_rows_linger_through_dealloc_and_tick_down_by_one() -> void:
	var d := _def()
	if d == null:
		return
	var n: SkillNode = await _owned_node()
	n.get_combat().apply_status(d, 2.0, &"A", 1)
	n.get_combat().apply_status(d, 1.0, &"B", 2)
	_alloc.force_deallocate(n)
	assert_not_null(_row(n, d.id, &"A"), "row A survives deallocation")
	assert_not_null(_row(n, d.id, &"B"), "row B survives deallocation")
	n.get_combat().tick_statuses()
	var a := _row(n, d.id, &"A")
	assert_not_null(a, "row A survives one tick")
	if a != null:
		assert_eq(a.power, 1.0, "one tick takes 2 stacks to 1")


# (f) the remembered sight is world state: it round-trips the snapshot
func test_remembered_sight_round_trips_the_snapshot() -> void:
	var source: Graph = autofree(_GRAPH_SCENE.instantiate())
	add_child(source)
	var target: Graph = autofree(_GRAPH_SCENE.instantiate())
	add_child(target)
	await get_tree().process_frame
	var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
	source.add_skill_node(n)
	await get_tree().process_frame
	n.last_owned_vision = 437.5
	GraphSnapshot.decode(GraphSnapshot.encode(source), target)
	var decoded := target.get_by_stable_id(source.get_stable_id(n))
	assert_not_null(decoded, "the node decoded")
	if decoded != null:
		assert_eq(decoded.last_owned_vision, 437.5, "the remembered sight is carried")
