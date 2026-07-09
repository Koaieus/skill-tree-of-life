extends GutTest

## Regression test for #151 — edges must render below SkillNodes. The bug:
## Edge.sensed's setter pinned the un-sensed path at absolute z 0
## (GRAPH_DEFAULT, same absolute z as a SkillNode) once VisionSystem had ever
## toggled `sensed` true then back to false, so scene-tree order (Edges after
## Nodes in graph.tscn) drew the edge on top. See ui/z_layers.gd for the band
## table and graph/edge.gd for the fix.

const ZLayers = preload("res://ui/z_layers.gd")
const _EDGE_SCENE := preload("res://graph/edge.tscn")


func test_edge_band_sits_between_aura_and_graph_default() -> void:
	assert_lt(ZLayers.EDGE, ZLayers.GRAPH_DEFAULT, "EDGE must draw below graph-default (SkillNode) band")
	assert_gt(ZLayers.EDGE, ZLayers.AURA, "EDGE must draw above the aura wash")


func test_fresh_edge_instance_rests_on_edge_band() -> void:
	var edge := _EDGE_SCENE.instantiate() as Edge
	add_child_autofree(edge)
	await get_tree().process_frame

	assert_false(edge.z_as_relative, "a fresh edge must use absolute z so parent/sibling order can't override it")
	assert_eq(edge.z_index, ZLayers.EDGE)


func test_sensed_round_trip_returns_to_edge_band_absolute() -> void:
	var edge := _EDGE_SCENE.instantiate() as Edge
	add_child_autofree(edge)
	await get_tree().process_frame

	edge.sensed = true
	assert_eq(edge.z_index, ZLayers.SENSED)

	# sensed's setter early-returns when unchanged, so go true -> false to
	# actually exercise the un-sensed path (this is the regression path).
	edge.sensed = false
	assert_eq(edge.z_index, ZLayers.EDGE, "un-sensed edge must return to the EDGE band, not GRAPH_DEFAULT (0)")
	assert_false(edge.z_as_relative, "un-sensed edge must stay absolute, not flip back to relative")
