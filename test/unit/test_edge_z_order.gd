extends GutTest

## Regression test for #151 — edges must render below SkillNodes. The bug:
## Edge.sensed's setter pinned the un-sensed path at absolute z 0
## (GRAPH_DEFAULT, same absolute z as a SkillNode) once VisionSystem had ever
## toggled `sensed` true then back to false, so scene-tree order (Edges after
## Nodes in graph.tscn) drew the edge on top. See ui/z_layers.gd for the band
## table and graph/edge.gd for the fix.
##
## #413, then extended to fold self-loops into the same shared MultiMesh:
## every edge now self-shades in a shared MultiMesh fragment shader instead
## of escaping FogOverlay's opaque quad via z-order, so `sensed` no longer
## touches `z_index` for ANY edge, self-loops included — it folds into the
## MultiMesh vis_state push instead (see `graph/edge_mesh.gdshader`'s header
## comment for the +10 ring-vs-bar offset).

const ZLayers = preload("res://ui/z_layers.gd")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")


func test_edge_band_sits_between_aura_and_graph_default() -> void:
	assert_lt(ZLayers.EDGE, ZLayers.GRAPH_DEFAULT, "EDGE must draw below graph-default (SkillNode) band")
	assert_gt(ZLayers.EDGE, ZLayers.AURA, "EDGE must draw above the aura wash")


func test_fresh_edge_instance_rests_on_edge_band() -> void:
	var edge := _EDGE_SCENE.instantiate() as Edge
	add_child_autofree(edge)
	await get_tree().process_frame

	assert_false(edge.z_as_relative, "a fresh edge must use absolute z so parent/sibling order can't override it")
	assert_eq(edge.z_index, ZLayers.EDGE)


func test_regular_edge_sensed_round_trip_does_not_touch_z_index() -> void:
	var a := _SKILL_NODE_SCENE.instantiate() as SkillNode
	var b := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(a)
	add_child_autofree(b)
	var edge := _EDGE_SCENE.instantiate() as Edge
	add_child_autofree(edge)
	edge.from = a
	edge.to = b
	await get_tree().process_frame

	assert_eq(edge.z_index, ZLayers.EDGE, "a regular edge starts on the EDGE band")
	edge.sensed = true
	assert_eq(edge.z_index, ZLayers.EDGE, "sensed no longer promotes a regular edge's z_index (#413) — it self-shades instead")
	edge.sensed = false
	assert_eq(edge.z_index, ZLayers.EDGE)


func test_self_loop_sensed_round_trip_does_not_touch_z_index() -> void:
	var a := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(a)
	var edge := _EDGE_SCENE.instantiate() as Edge
	add_child_autofree(edge)
	edge.from = a
	edge.to = a
	await get_tree().process_frame

	assert_true(edge.is_self_loop)
	assert_eq(edge.z_index, ZLayers.EDGE, "a self-loop starts on the EDGE band, same as every edge")
	edge.sensed = true
	assert_eq(edge.z_index, ZLayers.EDGE, "sensed must not touch a self-loop's z_index — it self-shades instead")
	edge.sensed = false
	assert_eq(edge.z_index, ZLayers.EDGE)


func test_self_loop_sensed_round_trip_offsets_vis_state_by_the_loop_marker() -> void:
	var a := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(a)
	var edge := _EDGE_SCENE.instantiate() as Edge
	add_child_autofree(edge)
	edge.from = a
	edge.to = a
	await get_tree().process_frame

	# +10 is the shader's ring-vs-bar marker (graph/edge_mesh.gdshader header
	# comment) — a self-loop's vis_state must always carry it, sensed or not,
	# or the shared shader would draw the ring as a degenerate bar instead.
	assert_eq(edge.render_vis_state, 10.0 + Edge.VIS_VISIBLE, "a fresh self-loop is visible + loop-marked")
	edge.sensed = true
	assert_eq(edge.render_vis_state, 10.0 + Edge.VIS_SENSED, "a sensed self-loop stays loop-marked")
	edge.sensed = false
	assert_eq(edge.render_vis_state, 10.0 + Edge.VIS_VISIBLE)
