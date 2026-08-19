extends GutTest

## Perf-shape coverage for [method VisionSystem._recompute] at the scale this
## project actually targets (`.claude/rules/skill-node-scale.md`: ~2000 nodes,
## a few hundred owned). Two properties, both regressions that were real:
##
## 1. [b]One allocation costs exactly one recompute.[/b] `_request_recompute`
##    debounces a burst of `value_changed` into a single deferred pass, and
##    `_recompute` itself re-binds stat signals — if a rebind ever re-armed the
##    pending flag, the recompute would re-defer itself every frame and present
##    as a multi-second stall with no threading in sight. This test pins that it
##    doesn't. (Measured 2026-08-17: it doesn't, which killed that hypothesis.)
##
## 2. [b]Recompute cost does not scale with the owned count.[/b] The visibility
##    pass used to be a per-node linear scan over every owned node's circle —
##    2000 x 200 = 400k GDScript iterations, 13.3ms of a 19.4ms recompute.
##    [VisionCircles]' grid made it a bounded local lookup. Asserting a
##    wall-clock ceiling would be machine-dependent, so this asserts the
##    *ratio* between a large and a small owned set, which is the property the
##    index provides and the scan did not.
##
## The fixture is a real 45x45 grid graph with real SkillNode scenes, because
## the thing under test is exactly the cost of walking that many of them.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

const _SIDE := 45              ## 45 x 45 = 2025 SkillNodes.
const _SPACING := 150.0
const _MANY_OWNED := 200
const _FEW_OWNED := 8

var _graph: Graph
var _alloc: AllocationSystem
var _vision: VisionSystem
var _entity: Entity
var _nodes: Array[SkillNode] = []


func _idx(x: int, y: int) -> int:
	return y * _SIDE + x


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_nodes = []
	for y in _SIDE:
		for x in _SIDE:
			var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
			sn.name = "N_%d_%d" % [x, y]
			sn.position = Vector2(x * _SPACING, y * _SPACING)
			_graph.skill_nodes_container.add_child(sn)
			_nodes.append(sn)
	for y in _SIDE:
		for x in _SIDE:
			if x + 1 < _SIDE:
				_add_edge(_nodes[_idx(x, y)], _nodes[_idx(x + 1, y)])
			if y + 1 < _SIDE:
				_add_edge(_nodes[_idx(x, y)], _nodes[_idx(x, y + 1)])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)
	await get_tree().process_frame

	_vision = VisionSystem.new()
	_vision.graph = _graph
	_vision.allocation_system = _alloc
	_vision.viewers = [_entity]
	add_child_autofree(_vision)
	await get_tree().process_frame


func _add_edge(a: SkillNode, b: SkillNode) -> Edge:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)
	return e


## Owns a roughly square contiguous blob centred on the grid — the shape a real
## run produces, and the one that makes the union of circles densest.
func _own_block(count: int) -> void:
	var side := int(ceil(sqrt(float(count))))
	var ox := int((_SIDE - side) / float(2))
	var oy := int((_SIDE - side) / float(2))
	var done := 0
	for y in side:
		for x in side:
			if done >= count:
				return
			_alloc.force_allocate(_entity, _nodes[_idx(ox + x, oy + y)])
			done += 1


## Median of several timed recomputes, in usec. Median rather than min so one
## unlucky sample can't pass a genuinely slow build, and rather than mean so a
## GC pause can't fail a fast one.
func _median_recompute_usec(samples: int = 7) -> float:
	var times: Array[int] = []
	for i in samples:
		var t := Time.get_ticks_usec()
		_vision._recompute()
		times.append(Time.get_ticks_usec() - t)
	times.sort()
	return float(times[int(times.size() / float(2))])


func test_one_allocation_triggers_exactly_one_recompute() -> void:
	_own_block(_MANY_OWNED)
	for i in 5:
		await get_tree().process_frame

	var recomputes: Array[int] = []
	_vision.visibility_changed.connect(func() -> void: recomputes.append(1))

	# One more node, at the blob's edge, then a generous number of frames — a
	# self-re-arming recompute would land one pass per frame for all of them.
	_alloc.force_allocate(_entity, _nodes[_idx(int(_SIDE / float(2)) - 1, int(_SIDE / float(2)) - 1)])
	for i in 60:
		await get_tree().process_frame

	assert_eq(recomputes.size(), 1,
		"one allocation must settle into exactly one recompute, not one per frame")
	assert_false(_vision._recompute_pending,
		"and must leave nothing pending behind it")


func test_recompute_cost_does_not_track_the_owned_count() -> void:
	_own_block(_FEW_OWNED)
	for i in 5:
		await get_tree().process_frame
	var few := _median_recompute_usec()

	_own_block(_MANY_OWNED)
	for i in 5:
		await get_tree().process_frame
	var many := _median_recompute_usec()

	var ratio := many / maxf(few, 1.0)
	gut.p("recompute: %d owned = %.0fus, %d owned = %.0fus (%.2fx)"
		% [_FEW_OWNED, few, _MANY_OWNED, many, ratio])
	# 25x the owned nodes. Measured on this fixture: 1.75x indexed, 5.03x with
	# the index swapped back out for the old linear scan (checked by actually
	# doing that, not by extrapolating). Only the genuinely-scaling work grows —
	# per-owned stat reads, the sensed traversal's larger frontier. 3.0 sits
	# between the two with room for a slower machine on either side.
	#
	# Caveat for whoever reads a pass here as reassurance: the ratio is diluted
	# by the recompute's owned-count-INDEPENDENT cost (~3.3ms of the 3.3ms
	# baseline). Add fixed work to `_recompute` and this guard gets easier to
	# pass, not harder. It catches losing the index; it is not a cost ceiling.
	assert_lt(ratio, 3.0,
		"%dx the owned nodes must not cost anywhere near %dx the recompute"
		% [int(_MANY_OWNED / float(_FEW_OWNED)), int(_MANY_OWNED / float(_FEW_OWNED))])
