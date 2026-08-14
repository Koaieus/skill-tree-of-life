extends GutTest

## Regression test for #151 — edges must render below SkillNodes. The bug:
## Edge.sensed's setter pinned the un-sensed path at absolute z 0
## (GRAPH_DEFAULT, same absolute z as a SkillNode) once VisionSystem had ever
## toggled `sensed` true then back to false, so scene-tree order (Edges after
## Nodes in graph.tscn) drew the edge on top. See ui/z_layers.gd for the band
## table and graph/edge.gd for the fix.
##
## #413 narrowed the z-index dance to SELF-LOOPS only: regular edges now
## self-shade in a shared MultiMesh fragment shader instead of escaping
## FogOverlay's opaque quad via z-order, so `sensed` no longer touches
## `z_index` for them at all — only a self-loop (from == to) still does.

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


func test_self_loop_sensed_round_trip_returns_to_edge_band_absolute() -> void:
	var a := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child_autofree(a)
	var edge := _EDGE_SCENE.instantiate() as Edge
	add_child_autofree(edge)
	edge.from = a
	edge.to = a
	await get_tree().process_frame

	assert_true(edge.is_self_loop)
	edge.sensed = true
	# The ABSOLUTE sensed band. `EDGE + SENSED` is 991 — below the opaque
	# FogOverlay quad at ZLayers.FOG — so the old additive value meant a sensed
	# self-loop was painted over and read as nothing at all.
	assert_eq(edge.z_index, ZLayers.SENSED,
		"a sensed self-loop must sit ABOVE the fog band, or the breadcrumb never reads")
	assert_gt(edge.z_index, ZLayers.FOG,
		"the whole point of the sensed promotion is punching through the fog")

	# sensed's setter early-returns when unchanged, so go true -> false to
	# actually exercise the un-sensed path (this is the regression path).
	edge.sensed = false
	assert_eq(edge.z_index, ZLayers.EDGE, "un-sensed self-loop must return to the EDGE band, not GRAPH_DEFAULT (0)")
	assert_false(edge.z_as_relative, "un-sensed self-loop must stay absolute, not flip back to relative")
