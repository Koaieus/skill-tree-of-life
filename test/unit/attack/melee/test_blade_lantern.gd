extends GutTest

## A melee blade vertex whose riders land the scout status carries one
## lantern marker that follows the drawn vertex; a plain blade carries none,
## and nothing outlives the blade.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _WATCHTOWER := preload("res://skill_node/addons/defs/watchtower_addon.tscn")
const _GROUP := &"vision_lanterns"


func _build_blade(scout_member: bool, autofree: bool = true) -> SkillBlade:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var pivot := _SKILL_NODE_SCENE.instantiate() as SkillNode
	var member := _SKILL_NODE_SCENE.instantiate() as SkillNode
	graph.skill_nodes_container.add_child(pivot)
	graph.skill_nodes_container.add_child(member)
	member.position = Vector2(80.0, 0.0)
	if scout_member:
		member.add_child(_WATCHTOWER.instantiate())

	var blade := SkillBlade.SCENE.instantiate() as SkillBlade
	if autofree:
		add_child_autofree(blade)
	else:
		add_child(blade)
	var nodes: Array[SkillNode] = [pivot, member]
	blade.build_from_skill_nodes(nodes, pivot, [[pivot, member]], null, BladeVertexFill.new())
	return blade


func _traj() -> BladeTrajectory:
	var traj := BladeTrajectory.new()
	traj.sample_dt = 0.1
	traj.samples = []
	for i in 11:
		var a := float(i) * 0.15
		traj.samples.append(PackedVector2Array([Vector2.ZERO, Vector2(80.0, 0.0).rotated(a)]))
	return traj


func _lanterns() -> Array[Node]:
	return get_tree().get_nodes_in_group(_GROUP)


func test_scout_vertex_carries_one_lantern_at_its_drawn_position() -> void:
	var blade := _build_blade(true)
	var visuals := blade.get_node_visuals()
	var traj := _traj()
	for t in [0.25, 0.8]:
		blade._apply_playback_frame(t, traj, [], true)
		var lanterns := _lanterns()
		assert_eq(lanterns.size(), 1, "one marker for the one scout vertex at t=%s" % t)
		if lanterns.size() == 1:
			var lantern := lanterns[0] as Node2D
			assert_lt(lantern.global_position.distance_to(visuals[1].global_position), 1.0,
					"marker sits on the drawn scout vertex at t=%s" % t)
			assert_eq(lantern.get(&"source"), blade.owned_by, "source is the wielder")


func test_plain_blade_carries_no_lantern() -> void:
	_build_blade(false)
	assert_eq(_lanterns().size(), 0, "no scout rider, no marker")


func test_no_marker_outlives_the_blade() -> void:
	var blade := _build_blade(true, false)
	assert_eq(_lanterns().size(), 1, "precondition: the scout blade is lit")
	blade.free()
	assert_eq(_lanterns().size(), 0, "freeing the blade leaves no marker")
