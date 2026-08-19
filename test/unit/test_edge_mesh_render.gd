extends GutTest

## #413, extended to fold self-loops into the same batch — no Edge owns a
## Line2D/`_draw()` of its own; every edge (including self-loops) pushes a
## transform + colour(s) into its Graph's shared `edge_mesh`
## MultiMeshInstance2D slot instead. Covers the acceptance spec's functional
## criteria: instance count tracks live edges (self-loops included), regular
## per-instance transform places the quad between endpoints, self-loop
## transform places a ring around its node, and lit/unlit/sensed/hidden all
## land in the right colour + vis-state channel for both shapes. See
## test_edge_z_order.gd / test_edge_zoom_width.gd for self-loop z-order/zoom
## coverage.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")

var _graph: Graph
var _nodes: Array[SkillNode]


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_nodes = []
	for i in 3:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		sn.global_position = Vector2(i * 100.0, 0.0)
		_graph.add_skill_node(sn)
		_nodes.append(sn)


## `visible_instance_count` (not `instance_count`) is the live-edge-count
## signal — `instance_count` is buffer CAPACITY, grown by doubling and never
## shrunk (see `Graph._grow_edge_mesh_capacity`'s docstring: any write to
## `instance_count` discards the whole GPU buffer on a real renderer, so it's
## touched only rarely, on purpose).
func test_visible_instance_count_tracks_added_and_removed_edges() -> void:
	var e1 := _graph.add_edge(_nodes[0], _nodes[1])
	await get_tree().process_frame
	assert_eq(_graph.edge_mesh.multimesh.visible_instance_count, 1)

	var e2 := _graph.add_edge(_nodes[1], _nodes[2])
	await get_tree().process_frame
	assert_eq(_graph.edge_mesh.multimesh.visible_instance_count, 2)

	_graph.remove_edge(e1)
	await get_tree().process_frame
	assert_eq(_graph.edge_mesh.multimesh.visible_instance_count, 1)

	_graph.remove_edge(e2)
	await get_tree().process_frame
	assert_eq(_graph.edge_mesh.multimesh.visible_instance_count, 0)


## Capacity grows to fit but never shrinks back down on removal — reallocating
## on every edge count dip would re-trigger the same buffer-discard problem
## `_grow_edge_mesh_capacity` exists to amortize away.
func test_instance_count_capacity_grows_but_never_shrinks() -> void:
	var e1 := _graph.add_edge(_nodes[0], _nodes[1])
	await get_tree().process_frame
	var capacity_after_one: int = _graph.edge_mesh.multimesh.instance_count
	assert_gt(capacity_after_one, 0)

	_graph.add_edge(_nodes[1], _nodes[2])
	await get_tree().process_frame
	assert_gte(_graph.edge_mesh.multimesh.instance_count, capacity_after_one)

	_graph.remove_edge(e1)
	await get_tree().process_frame
	assert_eq(_graph.edge_mesh.multimesh.instance_count, capacity_after_one)


## Regression for the #413 follow-up: the original bug was `instance_count`
## bumped by exactly 1 per edge add, and Godot's `MultiMesh.instance_count`
## setter reallocates (and silently DISCARDS) the whole GPU buffer on every
## write — confirmed against a real renderer, invisible under the headless
## dummy driver this suite runs on (see the NOTE at the bottom of this file).
## Every edge past the first got wiped back to a zero-scale quad by the NEXT
## edge's registration, so only the most-recently-added edge ever actually
## rendered. A doubling capacity strategy makes growth strictly less frequent
## than edge count once past the initial floor — assert that shape directly,
## since it's the one thing this class of bug changes that a headless test
## CAN see (`instance_count` is a plain int and round-trips fine).
func test_capacity_grows_by_doubling_not_per_edge() -> void:
	var chain: Array[SkillNode] = []
	for i in 12:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "Chain%d" % i
		sn.global_position = Vector2(i * 100.0, 500.0)
		_graph.add_skill_node(sn)
		autofree(sn)
		chain.append(sn)

	var capacities: Array[int] = []
	for i in 11:
		_graph.add_edge(chain[i], chain[i + 1])
		await get_tree().process_frame
		capacities.append(_graph.edge_mesh.multimesh.instance_count)

	# 11 edges added one at a time; a per-edge-reallocation bug would produce
	# 11 distinct capacity values (one bump per add). Doubling produces far
	# fewer distinct capacities than edges added.
	var distinct_capacities := {}
	for c in capacities:
		distinct_capacities[c] = true
	assert_lt(distinct_capacities.size(), capacities.size())


func test_transform_places_quad_between_endpoints() -> void:
	var edge := _graph.add_edge(_nodes[0], _nodes[1])
	await get_tree().process_frame

	# Not raw centre-to-centre: `SkillNode.segment_between` trims to each
	# node's rim (see skill_node.gd) — same segment the old Line2D path drew.
	var seg := SkillNode.segment_between(_nodes[0], _nodes[1])
	var a: Vector2 = seg[0]
	var b: Vector2 = seg[1]
	assert_almost_eq(edge.render_transform.get_origin(), (a + b) * 0.5, Vector2(0.01, 0.01))
	assert_almost_eq(edge.render_transform.x.length(), a.distance_to(b), 0.01)
	assert_almost_eq(edge.render_transform.get_rotation(), (b - a).angle(), 0.001)


func test_unowned_edge_pushes_unlit_visible_state() -> void:
	var edge := _graph.add_edge(_nodes[0], _nodes[1])
	await get_tree().process_frame

	assert_eq(edge.render_vis_state, Edge.VIS_VISIBLE)
	assert_almost_eq(edge.render_color_a.a, edge.unlit_alpha, 0.0001)


func test_shared_owner_lifts_both_endpoint_colours() -> void:
	var entity_owner := Entity.new()
	add_child_autofree(entity_owner)
	_nodes[0].owned_by = entity_owner
	_nodes[1].owned_by = entity_owner
	var edge := _graph.add_edge(_nodes[0], _nodes[1])
	await get_tree().process_frame

	assert_true(edge.is_lit())
	assert_almost_eq(edge.render_color_a.a, edge.lit_alpha, 0.0001)
	# The emissive lift raises rgb above the unlifted archetype tint whenever
	# the base colour isn't pure black (SkillNode's default tint is DIM_GRAY).
	var unlit_equivalent := edge._display_color(_nodes[0].base_type_color, true)
	assert_gt(edge.render_color_a.r, unlit_equivalent.r)


func test_sensed_ignores_vision_visible_and_forces_sensed_state() -> void:
	var edge := _graph.add_edge(_nodes[0], _nodes[1])
	await get_tree().process_frame

	edge.vision_visible = false
	edge.sensed = true
	assert_eq(edge.render_vis_state, Edge.VIS_SENSED)
	assert_almost_eq(edge.render_color_a.a, edge.sensed_alpha, 0.0001)


func test_hidden_when_not_sensed_and_not_vision_visible() -> void:
	var edge := _graph.add_edge(_nodes[0], _nodes[1])
	await get_tree().process_frame

	edge.vision_visible = false
	assert_eq(edge.render_vis_state, Edge.VIS_HIDDEN)


func test_self_loop_gets_a_slot_in_the_same_shared_mesh() -> void:
	var before: int = _graph.edge_mesh.multimesh.visible_instance_count
	var loop := _graph.add_edge(_nodes[0], _nodes[0])
	await get_tree().process_frame

	assert_true(loop.is_self_loop)
	assert_eq(_graph.edge_mesh.multimesh.visible_instance_count, before + 1, "a self-loop registers into the same slot bookkeeping as a regular edge")


func test_self_loop_transform_centres_a_ring_scaled_to_its_radius() -> void:
	var loop := _graph.add_edge(_nodes[0], _nodes[0])
	await get_tree().process_frame

	# Loop centre sits offset from the node along its bisector direction, not
	# AT the node centre — but it must stay within a couple of node radii, and
	# the transform's uniform scale must be positive (a degenerate/zero-size
	# ring would mean the radius never made it into the push).
	var dist := loop.render_transform.get_origin().distance_to(_nodes[0].global_position)
	assert_gt(dist, 0.0)
	assert_lt(dist, _nodes[0].radius * 3.0)
	assert_gt(loop.render_transform.x.length(), 0.0)
	assert_almost_eq(loop.render_transform.x.length(), loop.render_transform.y.length(), 0.01, "a ring's bounding quad must be scaled uniformly, not stretched like a bar")


## Drift guard for the additive-margin fix (see `Edge.SELF_LOOP_MARGIN`'s
## docstring): the quad's half-extent must contain the ring's true outer edge
## — `loop_radius + half_width_world` — at the loosest zoom the camera can
## reach (`GraphCamera.MIN_ZOOM`) with the material's authored `width`. A
## multiplicative pad can't guarantee this for small nodes; this pins the
## additive relationship so a future edit to `width` or `MIN_ZOOM` without
## updating `Edge.SELF_LOOP_MARGIN` (and its shader-side twin) fails loudly
## instead of silently mis-sizing every self-loop ring again.
func test_self_loop_margin_covers_worst_case_stroke_width() -> void:
	var material := load("res://graph/edge_mesh_material.tres") as ShaderMaterial
	var width: float = material.get_shader_parameter("width")
	var worst_case_half_width: float = (width * 0.5) / GraphCamera.MIN_ZOOM
	assert_gt(Edge.SELF_LOOP_MARGIN, worst_case_half_width, "SELF_LOOP_MARGIN must exceed the worst-case stroke half-width, with room left for AA")


func test_self_loop_pushes_one_colour_into_both_channels_offset_by_the_loop_marker() -> void:
	var loop := _graph.add_edge(_nodes[0], _nodes[0])
	await get_tree().process_frame

	assert_eq(loop.render_color_a, loop.render_color_b, "a self-loop has one endpoint — no gradient, both channels carry the same colour")
	assert_eq(loop.render_vis_state, 10.0 + Edge.VIS_VISIBLE, "a self-loop's vis_state must carry the shader's +10 ring marker (graph/edge_mesh.gdshader)")


## NOTE: no test reads back `mm.get_instance_color`/`get_instance_transform_2d`
## etc. — confirmed live (not just here) that Godot's headless dummy rendering
## backend no-ops MultiMesh instance-data writes entirely: even a bare
## `RenderingServer.multimesh_instance_set_color` / `_get_color` round-trip
## returns the unset default under `--headless`. `Edge.render_transform`/
## `render_color_a`/`render_color_b`/`render_vis_state` exist specifically so
## this suite has something real to assert against; `instance_count` and
## `visible_instance_count` are plain ints and DO round-trip (see the two
## tests above), which is why those read the multimesh directly and the rest
## don't.
