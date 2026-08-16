extends GutTest

## #455: ClampAddon renders no sprite — instead a clamped node's incident
## edges widen near that node. The widening itself lives entirely in the
## shader (`graph/edge_mesh.gdshader`'s `width_mult`), which a headless GUT
## run can't compile or measure (see `.claude/rules/godot-shaders.md`) — this
## suite only pins the CPU-side contract feeding it: the packed clamp code in
## `Edge.render_vis_state` (see `Edge._clamp_code`), self-loop exemption, live
## attach/detach updates, and `SkillNode.has_addon`.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _CLAMP_ADDON_SCENE := preload("res://skill_node/addons/clamp_addon.tscn")

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


func _clamp(node: SkillNode) -> ClampAddon:
	var addon := _CLAMP_ADDON_SCENE.instantiate() as ClampAddon
	node.add_child(addon)
	return addon


func test_neither_endpoint_clamped_leaves_vis_state_unchanged() -> void:
	var edge := _graph.add_edge(_nodes[0], _nodes[1])
	await get_tree().process_frame

	assert_eq(edge.render_vis_state, Edge.VIS_VISIBLE)


func test_only_from_clamped_packs_code_1() -> void:
	_clamp(_nodes[0])
	var edge := _graph.add_edge(_nodes[0], _nodes[1])
	await get_tree().process_frame

	assert_eq(edge.render_vis_state, Edge.VIS_VISIBLE + 100.0 * 1.0)


func test_only_to_clamped_packs_code_2() -> void:
	_clamp(_nodes[1])
	var edge := _graph.add_edge(_nodes[0], _nodes[1])
	await get_tree().process_frame

	assert_eq(edge.render_vis_state, Edge.VIS_VISIBLE + 100.0 * 2.0)


func test_both_endpoints_clamped_packs_code_3() -> void:
	_clamp(_nodes[0])
	_clamp(_nodes[1])
	var edge := _graph.add_edge(_nodes[0], _nodes[1])
	await get_tree().process_frame

	assert_eq(edge.render_vis_state, Edge.VIS_VISIBLE + 100.0 * 3.0)


func test_attaching_clamp_after_edge_exists_updates_vis_state_live() -> void:
	var edge := _graph.add_edge(_nodes[0], _nodes[1])
	await get_tree().process_frame
	assert_eq(edge.render_vis_state, Edge.VIS_VISIBLE, "sanity: no code before attach")

	_clamp(_nodes[0])
	await get_tree().process_frame

	assert_eq(edge.render_vis_state, Edge.VIS_VISIBLE + 100.0 * 1.0, "Edge.addons_changed subscription must push a fresh code with no from/to reassignment")


func test_detaching_clamp_drops_code_back_to_zero() -> void:
	var addon := _clamp(_nodes[0])
	var edge := _graph.add_edge(_nodes[0], _nodes[1])
	await get_tree().process_frame
	assert_eq(edge.render_vis_state, Edge.VIS_VISIBLE + 100.0 * 1.0, "sanity: code present before detach")

	_nodes[0].remove_child(addon)
	addon.queue_free()
	await get_tree().process_frame

	assert_eq(edge.render_vis_state, Edge.VIS_VISIBLE)


func test_self_loop_with_clamped_node_stays_exempt() -> void:
	_clamp(_nodes[0])
	var loop := _graph.add_edge(_nodes[0], _nodes[0])
	await get_tree().process_frame

	assert_eq(loop.render_vis_state, 10.0 + Edge.VIS_VISIBLE, "self-loops must never carry a clamp-code term, even when their node is clamped")


func test_has_addon_reflects_attach_and_detach() -> void:
	assert_false(_nodes[0].has_addon(ClampAddon))

	var addon := _clamp(_nodes[0])
	assert_true(_nodes[0].has_addon(ClampAddon))

	_nodes[0].remove_child(addon)
	addon.queue_free()
	await get_tree().process_frame
	assert_false(_nodes[0].has_addon(ClampAddon))


func test_has_addon_false_for_unrelated_script() -> void:
	_clamp(_nodes[0])
	assert_false(_nodes[0].has_addon(SkillNodeAddon), "ClampAddon's script is not SkillNodeAddon's own script")
