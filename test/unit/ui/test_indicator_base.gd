extends GutTest

## Indicator.min_screen_px: at canvas zoom z every member stroke draws at
## max(width, min_screen_px / z) world px, so it never thins below the floor
## on screen; radii stay world-space.

const _RETICLE := preload("res://ui/indicator/target_reticle.tscn")
const _M := 5.0


func _reticle_at_zoom(z: float) -> Node2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	vp.canvas_transform = Transform2D.IDENTITY.scaled(Vector2(z, z))
	var r := _RETICLE.instantiate() as Node2D
	r.set("min_screen_px", _M)
	vp.add_child(r)
	return r


func test_stroke_width_floors_at_min_screen_px_over_zoom() -> void:
	for z in [0.25, 1.0, 4.0]:
		var r := _reticle_at_zoom(z)
		await get_tree().process_frame
		var ring_w: float = r.get("ring_width")
		var arm_w: float = r.get("arm_width")
		assert_almost_eq(float(r.get_node("%Ring").get("width")), maxf(ring_w, _M / z), 0.0001,
				"ring stroke at zoom %s" % z)
		assert_almost_eq(float(r.get_node("%Spinner").get("arm_width")), maxf(arm_w, _M / z), 0.0001,
				"arm stroke at zoom %s" % z)


func test_radius_stays_world_space_under_zoom() -> void:
	var r := _reticle_at_zoom(0.25)
	await get_tree().process_frame
	var inner: float = r.get("radius") + float(r.get("arm_inner_offset"))
	assert_almost_eq(float(r.get_node("%Spinner").get("inner_radius")), inner, 0.0001)
