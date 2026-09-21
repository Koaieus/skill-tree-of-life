extends GutTest

## Scouted marks on [VisionSystem] (#1033): a [signal Events.node_scouted]
## seeds a vision circle for the viewer's group only, halves at the viewer's
## turn start through `effects/status/scouted.tres`, is gone below the floor,
## and a re-landing takes the max — never a sum.
##
## Layout (world units): A owns N0 at x=0 with vision_range 100. N5 sits at
## x=600 (out of A's sight), N6 at x=750 (150 past N5), N7 at x=710 (110 past
## N5). A 200 mark on N5 sees N6 and N7; halved to 100 it sees neither;
## refreshed to 120 it sees N7 alone. N0–N5 is an edge so N5 can be sensed.
##
## Like `test_vision_system.gd`, the fixture leaves `allocation_system` unset
## and drives `_recompute()` explicitly so every assert reads a settled state.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _vision: VisionSystem
var _a: Entity
var _b: Entity
var _n0: SkillNode
var _n5: SkillNode
var _n6: SkillNode
var _n7: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_n0 = _spawn("N0", 0.0)
	_n5 = _spawn("N5", 600.0)
	_n6 = _spawn("N6", 750.0)
	_n7 = _spawn("N7", 710.0)
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = _n0
	e.to = _n5
	_graph.edges_container.add_child(e)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_a = _entity("A")
	_b = _entity("B")
	await get_tree().process_frame
	_alloc.force_allocate(_a, _n0)
	_set_stat(&"vision_range", 100.0)

	_vision = VisionSystem.new()
	_vision.graph = _graph
	_vision.viewers = [_a]
	add_child_autofree(_vision)
	await get_tree().process_frame
	_vision._recompute()
	assert_false(_vision.is_visible(_n5), "fixture: N5 is out of A's own sight")


func _spawn(nm: String, x: float) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	sn.position = Vector2(x, 0.0)
	_graph.skill_nodes_container.add_child(sn)
	return sn


func _entity(nm: String) -> Entity:
	var en: Entity = autofree(Entity.new())
	en.display_name = nm
	en.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(en)
	return en


## Both vision stats are derived (a PER-scaled term rides on `base_value`),
## so solve for the base that lands the EFFECTIVE local value on N0.
func _set_stat(id: StringName, value: float) -> void:
	var s: Stat = _a.stat_board.get_stat(id)
	s.base_value = 0.0
	var derived: float = float(_n0.get_local_value(id))
	s.base_value = value - derived
	assert_almost_eq(float(_n0.get_local_value(id)), value, 0.001, "fixture: %s" % id)


func _scout(node: SkillNode, viewer: Entity, radius: float) -> void:
	Events.node_scouted.emit(node, viewer, radius)
	_vision._recompute()


func _tick(viewer: Entity) -> void:
	Events.turn_started.emit(viewer)
	_vision._recompute()


func test_a_mark_reveals_the_radius_to_the_firers_group_only() -> void:
	var other := VisionSystem.new()
	other.graph = _graph
	other.viewers = [_b]
	add_child_autofree(other)
	await get_tree().process_frame
	_scout(_n5, _a, 200.0)
	other._recompute()
	assert_true(_vision.is_visible(_n5), "the landing node is inside its own disc")
	assert_true(_vision.is_visible(_n6), "N6 at 150 is inside a 200 disc")
	assert_false(other.is_visible(_n6), "B's group does not see A's mark")
	assert_false(other.is_visible(_n5), "B's group does not see A's mark")


func test_the_mark_halves_at_the_firers_turn_start() -> void:
	_scout(_n5, _a, 200.0)
	_tick(_a)
	assert_true(_vision.is_visible(_n5), "a 100 disc still covers its centre")
	assert_false(_vision.is_visible(_n6), "N6 at 150 is outside the halved 100 disc")


func test_another_viewers_turn_does_not_decay_the_mark() -> void:
	_scout(_n5, _a, 200.0)
	_tick(_b)
	assert_true(_vision.is_visible(_n6), "B's turn start is not A's clock")


func test_the_mark_is_gone_below_the_floor() -> void:
	_scout(_n5, _a, 200.0)
	# power 4 → 2 → 1 → below 1 clears (scouted.tres: FRACTION 0.5, floor 50).
	for i in 3:
		_tick(_a)
	assert_false(_vision.is_visible(_n5), "three halvings of 200 sink below the 50 floor")


func test_relanding_takes_the_max_never_the_sum() -> void:
	_scout(_n5, _a, 200.0)
	_tick(_a)  # 100
	_scout(_n5, _a, 120.0)
	assert_true(_vision.is_visible(_n7), "N7 at 110 is inside the refreshed 120 disc")
	assert_false(_vision.is_visible(_n6), "N6 at 150 would only show under a summed 220")


func test_a_weaker_relanding_keeps_the_live_mark() -> void:
	_scout(_n5, _a, 200.0)
	_scout(_n5, _a, 120.0)
	assert_true(_vision.is_visible(_n6), "max(200, 120) keeps 200")


func test_the_def_owns_the_decay_rate() -> void:
	var def: StatusDef = _vision.scouted_def.duplicate() as StatusDef
	def.decay_per_tick = 0.75
	_vision.scouted_def = def
	_scout(_n5, _a, 200.0)
	_tick(_a)  # power 4 → 1
	assert_true(_vision.is_visible(_n5), "one quarter-tick keeps a 50 disc")
	_tick(_a)  # → 0.25 → cleared
	assert_false(_vision.is_visible(_n5), "the tres' rate, not code, sets the tick count")


func test_the_marks_circle_reaches_the_renderer() -> void:
	_vision.ease_rate = 0.0
	_scout(_n5, _a, 200.0)
	await get_tree().process_frame
	var found := false
	for src in _vision.get_vision_sources():
		if src.pos.is_equal_approx(_n5.global_position) and is_equal_approx(src.radius, 200.0):
			found = true
	assert_true(found, "get_vision_sources carries the mark's circle at N5 with radius 200")


func test_scouted_flag_is_written_for_the_local_group_only() -> void:
	var other := VisionSystem.new()
	other.graph = _graph
	other.viewers = [_b]
	add_child_autofree(other)
	await get_tree().process_frame
	_scout(_n5, _a, 200.0)
	assert_true(_n5.scouted, "A's machine marks the node scouted")
	other._recompute()
	assert_false(_n5.scouted, "B's machine recomputing writes its own (empty) view")


func test_pick_sensed_makes_a_sensed_only_node_pickable() -> void:
	_set_stat(&"sensor_range", 1.0)
	_vision._recompute()
	assert_true(_vision.is_sensed(_n5), "fixture: N5 is one hop from N0")
	assert_false(_n5.input_pickable, "sensed-only is not pickable by default")
	_vision.pick_sensed = true
	_vision._recompute()
	assert_true(_n5.input_pickable, "pick_sensed opens sensed-only nodes to input")
