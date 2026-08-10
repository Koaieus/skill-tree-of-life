extends GutTest

## #413 — regular edges no longer own a Line2D; they push a transform +
## endpoint colours into their Graph's shared `edge_mesh` MultiMeshInstance2D
## slot instead. Covers the acceptance spec's functional criteria: instance
## count tracks live edges, per-instance transform places the quad between
## endpoints, and lit/unlit/sensed/hidden all land in the right colour +
## vis-state channel. Self-loops are unaffected (out of scope) — see
## test_edge_z_order.gd / test_edge_zoom_width.gd for their coverage.

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


func test_instance_count_tracks_added_and_removed_edges() -> void:
	var e1 := _graph.add_edge(_nodes[0], _nodes[1])
	await get_tree().process_frame
	assert_eq(_graph.edge_mesh.multimesh.instance_count, 1)

	var e2 := _graph.add_edge(_nodes[1], _nodes[2])
	await get_tree().process_frame
	assert_eq(_graph.edge_mesh.multimesh.instance_count, 2)

	_graph.remove_edge(e1)
	await get_tree().process_frame
	assert_eq(_graph.edge_mesh.multimesh.instance_count, 1)

	_graph.remove_edge(e2)
	await get_tree().process_frame
	assert_eq(_graph.edge_mesh.multimesh.instance_count, 0)


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
	var owner := Entity.new()
	add_child_autofree(owner)
	_nodes[0].owned_by = owner
	_nodes[1].owned_by = owner
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


## NOTE: no test reads back `mm.get_instance_color`/`get_instance_transform_2d`
## etc. — confirmed live (not just here) that Godot's headless dummy rendering
## backend no-ops MultiMesh instance-data writes entirely: even a bare
## `RenderingServer.multimesh_instance_set_color` / `_get_color` round-trip
## returns the unset default under `--headless`. `Edge.render_transform`/
## `render_color_a`/`render_color_b`/`render_vis_state` exist specifically so
## this suite has something real to assert against; `instance_count` is a
## plain int and DOES round-trip (see the first test above), which is why
## that one reads the multimesh directly and the rest don't.
