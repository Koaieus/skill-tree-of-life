extends GutTest

## #414 — where [FogOverlay]'s O(elements) work is allowed to live.
##
## The fix that landed with this file is a SPLIT, and the split is the whole
## point: walking every SkillNode and every Edge is fine once per
## `visibility_changed` (once per allocation) and catastrophic once per
## `vision_render_tick` (every frame while a vision circle animates —
## 78 ms at 200 owned nodes on a 2000-node map, lane P's framerate collapse;
## see `test/perf/bench_fog_refresh_cost.gd`).
##
## `bench_fog_refresh_cost.gd` measures that the per-frame path got cheap. It
## cannot tell "the walk moved to the rarer signal" from "the walk moved
## somewhere the bench doesn't time" — both make the number drop. THIS file
## pins the structural half: which signal each pass hangs off, and that the
## per-frame path leaves element state alone.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _FOG_SCENE := preload("res://ui/fog_overlay/fog_overlay.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const ZLayers = preload("res://ui/z_layers.gd")

## Two nodes far enough apart that the default `vision_range` (~504px) reaches
## the owned one and nothing else — so one node classifies visible and the
## other hidden, in the same graph.
const _SPACING := 4000.0

var _graph: Graph
var _alloc: AllocationSystem
var _vision: VisionSystem
var _entity: Entity
var _nodes: Array[SkillNode]
var _fog: FogOverlay


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_nodes = []
	for i in 2:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		sn.position = Vector2(i * _SPACING, 0.0)
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = _nodes[0]
	e.to = _nodes[1]
	_graph.edges_container.add_child(e)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)
	await get_tree().process_frame
	_alloc.force_allocate(_entity, _nodes[0])

	_vision = VisionSystem.new()
	_vision.graph = _graph
	_vision.viewers = [_entity]
	add_child_autofree(_vision)
	await get_tree().process_frame

	_fog = _FOG_SCENE.instantiate() as FogOverlay
	_fog.vision_system = _vision
	add_child_autofree(_fog)
	await get_tree().process_frame
	_zero_the_sensor_budget()
	_vision._recompute()


## Without this N1 comes back SENSED (one hop along the edge), and a sensed node
## takes the classifier's early-out — it z-promotes itself. This fixture wants
## the genuinely-hidden branch, so the hop budget goes to zero.
##
## `sensor_range` is derived (the board adds a PER-scaled term on top of
## `base_value`), so solve for the base that lands the effective value on 0 —
## same trick as `test_vision_system.gd`'s `_set_budget`.
func _zero_the_sensor_budget() -> void:
	var s: Stat = _entity.stat_board.get_stat(&"sensor_range")
	s.base_value = 0.0
	var derived: float = float(_nodes[0].get_local_value(&"sensor_range"))
	s.base_value = -derived
	assert_eq(int(_nodes[0].get_local_value(&"sensor_range")), 0,
		"fixture: the sensor budget must be zero for N1 to read as hidden")


func test_visible_node_is_promoted_above_the_fog_band() -> void:
	assert_true(_vision.is_visible(_nodes[0]), "fixture: the owned node is visible")
	assert_eq(_nodes[0].z_index, ZLayers.GRAPH_DEFAULT + ZLayers.SENSED,
		"a visible node punches through the fog quad")
	assert_false(_nodes[0].z_as_relative,
		"the promotion must be absolute, or the graph's own z would fold in")


func test_hidden_node_stays_in_the_default_band_under_the_fog() -> void:
	assert_false(_vision.is_visible(_nodes[1]), "fixture: the far node is out of range")
	assert_eq(_nodes[1].z_index, ZLayers.GRAPH_DEFAULT,
		"a hidden node stays below the fog, which paints over it")
	assert_true(_nodes[1].z_as_relative)


## The CPU dimming pass is gone: nodes self-shade per-fragment in
## `inner_disk.gdshader` / `rim_ring.gdshader` against the shared
## `vision_field` globals. A `modulate.a` write would be the old pass creeping
## back — and it never reached the disk or rim anyway, since both shaders
## overwrite COLOR unconditionally.
func test_no_node_modulate_is_written() -> void:
	for n in _nodes:
		assert_eq(n.modulate.a, 1.0,
			"%s: fog darkness is a fragment-shader concern now, not modulate" % n.name)


func test_the_per_frame_tick_does_not_reclassify_elements() -> void:
	# Corrupt the classification by hand, then drive ONLY the per-frame path.
	# If `_refresh` still walked the graph it would repair this; it must not,
	# because that walk is what cost 78 ms/frame.
	_nodes[0].z_index = 42
	_nodes[1].z_index = 42
	_vision.vision_render_tick.emit()
	assert_eq(_nodes[0].z_index, 42, "vision_render_tick must not walk the graph")
	assert_eq(_nodes[1].z_index, 42, "vision_render_tick must not walk the graph")

	# The rarer signal is what owns the walk, and it repairs the same state.
	_vision.visibility_changed.emit()
	assert_eq(_nodes[0].z_index, ZLayers.GRAPH_DEFAULT + ZLayers.SENSED,
		"visibility_changed owns the O(elements) classification")
	assert_eq(_nodes[1].z_index, ZLayers.GRAPH_DEFAULT)


func test_edge_visibility_flag_still_reaches_edge() -> void:
	# Edges self-shade too (#413); the ONE thing that has to reach them from
	# here is the boolean, and it rides the same classification pass.
	var e: Edge = _graph.get_edges()[0]
	assert_true(e.vision_visible,
		"an edge with ONE visible endpoint renders — see the OR in the classifier")
