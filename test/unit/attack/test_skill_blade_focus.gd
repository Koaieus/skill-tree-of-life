extends GutTest

## #930 — the blade owns its centre of interest. [BladeTrajectory] stores the
## flat per-sample centroid (a sim fact); [SkillBlade] applies the pivot
## weight (a presentation fact) and writes the result to its authored
## `%FocusMarker`, event-driven: on build, on each placed vertex, on every
## playback frame. The pure weighting helper is asserted with the weight
## passed explicitly — the authored constant is the owner's to tune.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _DT := 0.05
const _W := 5.0


# --- acceptance 1: the trajectory's flat centroid -----------------------------

func _traj(poses: Array) -> BladeTrajectory:
	var traj := BladeTrajectory.new()
	traj.sample_dt = _DT
	for p in poses:
		traj.samples.append(PackedVector2Array(p))
	return traj


func test_the_centroid_of_a_sample_is_its_mean() -> void:
	var traj := _traj([[Vector2.ZERO, Vector2(100, 0)], [Vector2.ZERO, Vector2(0, 100)]])
	assert_almost_eq(traj.centroid_at(0.0), Vector2(50, 0), Vector2(0.001, 0.001))
	assert_almost_eq(traj.centroid_at(_DT), Vector2(0, 50), Vector2(0.001, 0.001))
	assert_almost_eq(traj.centroid_at(_DT * 0.5), Vector2(25, 25), Vector2(0.001, 0.001),
			"lerps between samples exactly like sample(t)")
	assert_almost_eq(traj.centroid_at(10.0), Vector2(0, 50), Vector2(0.001, 0.001),
			"and clamps at the end")
	assert_eq(BladeTrajectory.new().centroid_at(0.0), Vector2.ZERO, "empty is the origin")


func test_a_progressively_appended_trajectory_extends_its_centroids() -> void:
	# #796's progressive fill: samples arrive after the first read. The old
	# range is unchanged, the new range is correct, nothing is recomputed by
	# the resolver.
	var traj := _traj([[Vector2.ZERO, Vector2(100, 0)]])
	assert_almost_eq(traj.centroid_at(0.0), Vector2(50, 0), Vector2(0.001, 0.001))
	traj.samples.append(PackedVector2Array([Vector2.ZERO, Vector2(0, 200)]))
	assert_almost_eq(traj.centroid_at(_DT), Vector2(0, 100), Vector2(0.001, 0.001),
			"the appended sample is reachable")
	assert_almost_eq(traj.centroid_at(0.0), Vector2(50, 0), Vector2(0.001, 0.001),
			"and the old one is what it was")


# --- acceptance 4: the weighted-focus helper (migrated from the director) -----

func test_the_pivot_pulls_w_times_as_hard_as_any_other_vertex() -> void:
	# Pivot at the origin, one vertex at x=1000: flat centroid x=500, N=2.
	# The closed form over a pinned pivot must reproduce (w*0 + 1000) / (w+1).
	var center := SkillBlade.weighted_focus(Vector2.ZERO, Vector2(500, 0), 2, _W)
	assert_almost_eq(center.x, 1000.0 / 6.0, 0.001, "5 parts pivot to 1 part vertex")
	assert_almost_eq(center.y, 0.0, 0.001)


func test_the_centroid_translates_as_the_blade_sweeps() -> void:
	# Five vertices crossing from one side of the pivot to the other drag the
	# focus with them, symmetrically about the unmoving pivot.
	var before := Vector2(-600, 20) * 5.0 / 6.0  # flat mean incl. the pivot at 0
	var after := Vector2(600, 20) * 5.0 / 6.0
	var a := SkillBlade.weighted_focus(Vector2.ZERO, before, 6, _W)
	var b := SkillBlade.weighted_focus(Vector2.ZERO, after, 6, _W)
	assert_lt(a.x, -100.0, "the shot leans toward where the blade actually is")
	assert_gt(b.x, 100.0, "and follows it across")
	assert_almost_eq(a.x, -b.x, 0.001, "symmetrically about the unmoving pivot")


func test_an_empty_blade_tracks_the_pivot_alone() -> void:
	assert_eq(SkillBlade.weighted_focus(Vector2(7, 9), Vector2(7, 9), 1, _W),
			Vector2(7, 9), "a lone pivot is the pivot")
	assert_eq(SkillBlade.weighted_focus(Vector2(7, 9), Vector2.ZERO, 0, _W),
			Vector2(7, 9), "no vertices is the pivot, not a divide by zero")


# --- acceptance 2 + 3: the placed set and the marker ------------------------

func _blade_fixture() -> Dictionary:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var pivot := _SKILL_NODE_SCENE.instantiate() as SkillNode
	var member := _SKILL_NODE_SCENE.instantiate() as SkillNode
	graph.skill_nodes_container.add_child(pivot)
	graph.skill_nodes_container.add_child(member)
	member.position = Vector2(0.0, 600.0)
	await get_tree().process_frame
	var blade := SkillBlade.SCENE.instantiate() as SkillBlade
	add_child_autofree(blade)
	var nodes: Array[SkillNode] = [pivot, member]
	blade.build_from_skill_nodes(nodes, pivot, [[pivot, member]], null)
	return {"blade": blade, "pivot": pivot, "member": member}


func _rest_focus() -> Vector2:
	return SkillBlade.weighted_focus(Vector2.ZERO, Vector2(0, 300), 2,
			SkillBlade.FOCUS_PIVOT_WEIGHT)


func test_the_marker_is_authored_in_the_scene() -> void:
	var blade := SkillBlade.SCENE.instantiate() as SkillBlade
	add_child_autofree(blade)
	assert_not_null(blade.focus_marker(), "%FocusMarker is authored, never created in _ready")
	assert_true(blade.focus_marker() is Marker2D)


func test_a_built_blade_rests_its_marker_on_the_weighted_centre() -> void:
	var f: Dictionary = await _blade_fixture()
	var blade: SkillBlade = f["blade"]
	assert_true(blade.is_vertex_placed(0), "build places everything")
	assert_true(blade.is_vertex_placed(1))
	assert_almost_eq(blade.focus_marker().global_position, _rest_focus(),
			Vector2(0.001, 0.001), "rest = weighted centre over all vertices")


func test_the_form_in_places_the_pivot_first_and_the_marker_follows() -> void:
	var f: Dictionary = await _blade_fixture()
	var blade: SkillBlade = f["blade"]
	blade.form_in(0.0, 100.0, 0.0, 0.0, 0.0)
	assert_false(blade.is_vertex_placed(0), "form_in starts with none placed")
	assert_almost_eq(blade.focus_marker().global_position, Vector2.ZERO,
			Vector2(0.001, 0.001), "nothing placed: the pivot alone")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(blade.is_vertex_placed(0), "the pivot pops on the lead beat")
	assert_false(blade.is_vertex_placed(1), "the arm is 100s of stagger away")
	assert_almost_eq(blade.focus_marker().global_position, Vector2.ZERO,
			Vector2(0.001, 0.001), "an unplaced vertex does not pull")
	blade.form_instantly()
	assert_true(blade.is_vertex_placed(1), "a formed blade is fully placed")
	assert_almost_eq(blade.focus_marker().global_position, _rest_focus(),
			Vector2(0.001, 0.001), "and the marker lands on the rest centre")


func test_a_playback_frame_puts_the_marker_on_the_weighted_trajectory_centroid() -> void:
	var f: Dictionary = await _blade_fixture()
	var blade: SkillBlade = f["blade"]
	var traj := _traj([[Vector2.ZERO, Vector2(0, 600)], [Vector2.ZERO, Vector2(600, 0)]])
	var pending: Array[BladeHitEvent] = []
	blade._apply_playback_frame(_DT, traj, pending, true)
	var want := SkillBlade.weighted_focus(Vector2.ZERO, traj.centroid_at(_DT), 2,
			SkillBlade.FOCUS_PIVOT_WEIGHT)
	assert_almost_eq(blade.focus_marker().global_position, want, Vector2(0.001, 0.001),
			"mid-swing the marker rides centroid_at(t)")
	assert_almost_eq(want, Vector2(100, 0), Vector2(0.001, 0.001),
			"(sanity: the swept arm at x=600 pulls to 600/6)")
