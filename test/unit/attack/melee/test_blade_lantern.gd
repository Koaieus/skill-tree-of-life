extends GutTest

## A melee blade vertex whose riders land the scout status carries one
## lantern marker that follows the drawn vertex once the swing is committed
## ([method SkillBlade.arm_lanterns]); a plain blade carries none, the aim-time
## preview ghost carries none, and nothing outlives the blade.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _WATCHTOWER := preload("res://skill_node/addons/defs/watchtower_addon.tscn")
const _GROUP := &"vision_lanterns"


func _build_blade(scout_member: bool, autofree: bool = true) -> SkillBlade:
	var graph := TestWorld.create(self).graph
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
	blade.arm_lanterns()
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


func _preview_plan(_preview: MeleePreview) -> MeleeAttackPlan:
	var graph := TestWorld.create(self).graph
	var pivot := _SKILL_NODE_SCENE.instantiate() as SkillNode
	var member := _SKILL_NODE_SCENE.instantiate() as SkillNode
	graph.skill_nodes_container.add_child(pivot)
	graph.skill_nodes_container.add_child(member)
	member.position = Vector2(80.0, 0.0)
	member.add_child(_WATCHTOWER.instantiate())
	var plan := MeleeAttackPlan.new()
	plan.source = pivot
	plan.blade_nodes = [member]
	return plan


func test_preview_ghost_is_dark_until_the_commit_claims_it() -> void:
	var preview := MeleePreview.new()
	add_child_autofree(preview)
	var plan := _preview_plan(preview)
	preview._spawn_blade(plan)
	assert_not_null(preview.current_blade(), "precondition: the aim ghost is mounted")
	assert_eq(_lanterns().size(), 0, "the aim-time ghost lights nothing")

	preview.begin_windup(plan, null)
	await get_tree().process_frame  # the rebuild's old vertices are queue_freed
	assert_eq(_lanterns().size(), 1, "the committed swing lights its one scout vertex")
	var visuals := preview.current_blade().get_node_visuals()
	assert_lt(_lanterns()[0].global_position.distance_to(visuals[1].global_position), 1.0,
			"on the drawn scout vertex")


func test_lantern_radius_follows_the_scout_knob() -> void:
	var blade := _build_blade(true)
	var lanterns := _lanterns()
	assert_eq(lanterns.size(), 1, "precondition: one lit vertex")
	if lanterns.size() != 1:
		return
	# The authored rider is 0 stacks: nothing to size. Size a private copy —
	# the rider is the preloaded scene's shared sub-resource, so writing it in
	# place leaks into every later watchtower instance.
	var riders: Array = blade.state.vertex_on_hit[1]
	for i in riders.size():
		var effect: Variant = riders[i]
		if effect != null and effect.status_def() is ScoutStatus:
			var sized: Resource = effect.duplicate()
			sized.set(&"power", 4.0)
			riders[i] = sized
	blade.arm_lanterns()
	var expected := SkillBlade.scout_lantern_radius(blade.state, 1, blade._source_nodes[1])
	assert_gt(expected, 0.0, "the scout rider sizes the marker")
	assert_eq(lanterns[0].get(&"radius"), expected, "marker radius is the knob's, not the default")
	var scout: ScoutStatus = null
	for effect in blade.state.vertex_on_hit[1]:
		if effect != null and effect.status_def() is ScoutStatus:
			scout = effect.status_def()
			var stacks := roundi(float(effect.get(&"power"))) if &"power" in effect else 1
			assert_eq(lanterns[0].get(&"radius"), scout.lantern_radius_for(blade._source_nodes[1], stacks))
			break
	assert_not_null(scout, "a scout rider is on the vertex")


func test_launch_without_windup_lights_the_swing() -> void:
	var preview := MeleePreview.new()
	add_child_autofree(preview)
	var plan := _preview_plan(preview)
	preview._spawn_blade(plan)
	assert_eq(_lanterns().size(), 0, "precondition: the aim ghost is dark")
	preview.launch(plan)
	assert_eq(_lanterns().size(), 1, "launch's fallback path lights the scout vertex")
