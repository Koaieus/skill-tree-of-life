extends GutTest
## GimbalWorld (#1074): the one pure seam of the shared own-world 3D
## SubViewport — the camera mapping. The root viewport's world->pixels
## transform (canvas transform x stretch transform, i.e. what is actually
## drawn) plus the pixel size go in; the orthographic Camera3D's position and
## `size`, and the composite Sprite2D's world rect, come out. Convention:
## 1 3D unit = 1 world px, 2D +y down = 3D -y, camera looks down -Z from
## CAMERA_Z. Everything else in the unit is visual: measured, not asserted.


func test_identity_view_maps_pixels_one_to_one() -> void:
	var m := GimbalWorld.map_view(Transform2D.IDENTITY, Vector2(1920, 1080))
	assert_eq(m.get("camera_position"), Vector3(960, -540, GimbalWorld.CAMERA_Z),
			"camera hovers over the view centre, y flipped")
	assert_almost_eq(float(m.get("camera_size", 0.0)), 1080.0, 0.001,
			"ortho size is the visible height in world px (KEEP_HEIGHT)")
	assert_eq(m.get("sprite_position"), Vector2.ZERO, "sprite top-left at world origin")
	assert_eq(m.get("sprite_scale"), Vector2.ONE, "1 texel = 1 world px at zoom 1")


func test_zoomed_and_panned_view() -> void:
	# screen = 2 * world + (-1000, -500): zoom 2x, screen origin at world (500, 250).
	var xf := Transform2D(Vector2(2, 0), Vector2(0, 2), Vector2(-1000, -500))
	var m := GimbalWorld.map_view(xf, Vector2(1920, 1080))
	assert_eq(m.get("sprite_position"), Vector2(500, 250), "sprite top-left = world of pixel (0,0)")
	assert_eq(m.get("sprite_scale"), Vector2(0.5, 0.5), "sprite shrinks by the zoom so texels stay 1:1 on screen")
	assert_almost_eq(float(m.get("camera_size", 0.0)), 540.0, 0.001, "half the pixels' worth of world")
	assert_eq(m.get("camera_position"), Vector3(980, -520, GimbalWorld.CAMERA_Z),
			"camera over the world centre of the view, y flipped")


func test_stretch_is_folded_into_the_transform() -> void:
	# canvas_items stretch: a 1.5x stretch on top of a 1x camera reads as zoom 1.5.
	var xf := Transform2D(Vector2(1.5, 0), Vector2(0, 1.5), Vector2.ZERO)
	var m := GimbalWorld.map_view(xf, Vector2(2880, 1620))
	assert_almost_eq(float(m.get("camera_size", 0.0)), 1080.0, 0.001)
	assert_eq(m.get("sprite_scale"), Vector2(1.0 / 1.5, 1.0 / 1.5))
