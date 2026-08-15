extends GutTest

## #399 originally — Edge.width held constant on-screen coverage across
## camera zoom via a CPU `Line2D.width =` write on every broadcast. #413
## replaced that for regular edges with a shader that reads zoom straight off
## a global uniform at draw time (`graph/edge_mesh.gdshader`) — a camera zoom
## step now touches NOTHING on any Edge, self-loops included since they
## joined the same shared MultiMesh/shader: headless-untestable by design,
## there's no CPU write left to assert against. This file just pins that
## absence for both edge kinds.

const ZLayers = preload("res://ui/z_layers.gd")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")


func test_zoom_change_does_not_touch_regular_edge_render_transform() -> void:
	var a := _SKILL_NODE_SCENE.instantiate() as SkillNode
	var b := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(a)
	add_child_autofree(b)
	var edge := _EDGE_SCENE.instantiate() as Edge
	add_child_autofree(edge)
	edge.from = a
	edge.to = b
	await get_tree().process_frame

	var xf_before := edge.render_transform
	Events.camera_zoom_changed.emit(0.5)

	assert_eq(edge.render_transform, xf_before, "a zoom-only change must not recompute a regular edge's transform — width is shader-driven, not CPU-pushed")


func test_zoom_change_does_not_touch_self_loop_render_transform() -> void:
	var a := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(a)
	var edge := _EDGE_SCENE.instantiate() as Edge
	add_child_autofree(edge)
	edge.from = a
	edge.to = a
	await get_tree().process_frame

	var xf_before := edge.render_transform
	Events.camera_zoom_changed.emit(0.5)

	assert_eq(edge.render_transform, xf_before, "a zoom-only change must not recompute a self-loop's transform either — stroke width is shader-driven, loop radius is a fixed world-space quantity")
