extends GutTest
## Core-halos GIMBAL rewrite (#138): a real quaternion-composed nested-ring
## gyroscope, replacing the old co-planar-arc hack. This is explicitly an
## "eyeball it" aesthetic issue (see the issue body) — a pixel diff isn't the
## point. This guards what a screenshot can't: it doesn't crash, the
## front/back split (rings must pass over AND under the SkillNode's own
## disk) actually produces both layers, and the geometry is a pure function
## of anim_time so the back layer can never render stale while the front
## layer keeps animating — the failure mode flagged during planning.

const HalosScene := preload("res://skill_node/visuals/core_halos.tscn")


func test_gimbal_draws_without_error_and_has_a_back_layer() -> void:
	var halos := HalosScene.instantiate()
	add_child_autofree(halos)
	halos.halo_style = halos.CoreHaloStyle.GIMBAL
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(halos.is_gimbal_active(), "core is set to GIMBAL")
	var back := halos.get_node("GimbalBack")
	assert_not_null(back, "GIMBAL back layer exists")
	assert_eq(back.z_index, -1, "back layer sits behind InnerDisk/RimRing (z_index 0) via a relative offset")


func test_gimbal_geometry_splits_into_front_and_back_runs() -> void:
	var halos := HalosScene.instantiate()
	add_child_autofree(halos)
	halos.halo_style = halos.CoreHaloStyle.GIMBAL
	await get_tree().process_frame

	var runs: Dictionary = halos._gimbal_runs(halos.radius * halos.halo_scale, halos._halo_color)
	assert_gt(runs["front"].size(), 0, "some ring geometry passes in front of the disk")
	assert_gt(runs["back"].size(), 0, "some ring geometry passes behind the disk")


func test_gimbal_geometry_recomputes_from_anim_time() -> void:
	var halos := HalosScene.instantiate()
	add_child_autofree(halos)
	halos.halo_style = halos.CoreHaloStyle.GIMBAL
	await get_tree().process_frame

	halos.anim_time = 0.0
	var sum_a := _sum_all_points_x(halos._gimbal_runs(halos.radius * halos.halo_scale, halos._halo_color))
	halos.anim_time = 2.3
	var sum_b := _sum_all_points_x(halos._gimbal_runs(halos.radius * halos.halo_scale, halos._halo_color))

	assert_ne(sum_a, sum_b, "geometry is a pure function of anim_time — recomputed live, never cached/stale")


func _sum_all_points_x(runs: Dictionary) -> float:
	var total := 0.0
	for side in ["front", "back"]:
		for run in runs[side]:
			for p in run["in_pts"]:
				total += p.x
	return total
