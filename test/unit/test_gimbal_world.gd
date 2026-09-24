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


func test_clip_planes_split_the_world_at_the_ring_plane() -> void:
	# A2 (#1097): the camera sits at CAMERA_Z looking down -Z, so a clip
	# distance d is the plane z = CAMERA_Z - d. Front half = z > 0: far clip
	# AT z = 0. Back half = z < 0: near clip at z = 0, far past the rings.
	var front := GimbalWorld.clip_planes(true)
	assert_almost_eq(front.y, GimbalWorld.CAMERA_Z, 0.001, "front far clip is the ring plane z=0")
	assert_true(front.x > 0.0 and front.x < front.y, "front near is a positive distance short of the plane")
	var back := GimbalWorld.clip_planes(false)
	assert_almost_eq(back.x, GimbalWorld.CAMERA_Z, 0.001, "back near clip is the ring plane z=0")
	assert_true(back.y > back.x, "back far clip lies beyond the plane")
	# Together the two halves tile the visible depth with no gap and no overlap.
	assert_almost_eq(front.y, back.x, 0.001, "the halves meet exactly at z=0")


func test_acquire_parents_a_new_world_under_the_graph_not_the_host() -> void:
	# A live halo's host sits deep inside one SkillNode's ShaderStack: the
	# fallback world must land under the Graph (one canvas for the board),
	# never beside the host.
	var graph: Graph = (load("res://graph/graph.tscn") as PackedScene).instantiate()
	add_child_autofree(graph)
	var a := Node2D.new()
	graph.add_child(a)
	var b := Node2D.new()
	a.add_child(b)
	var host := Node2D.new()
	b.add_child(host)
	var world := GimbalWorld.acquire(host)
	assert_not_null(world, "acquire always yields a world")
	if world == null:
		return
	assert_eq(world.get_parent(), graph, "a new world is parented under the nearest Graph ancestor")
	var other := Node2D.new()
	graph.add_child(other)
	assert_eq(GimbalWorld.acquire(other), world, "a second host in the same viewport shares the one world")


func test_render_targets_sleep_with_no_rig_on_screen() -> void:
	var world: GimbalWorld = (load(GimbalWorld.SCENE) as PackedScene).instantiate()
	add_child_autofree(world)
	var back := world.get_node_or_null(^"WorldBack") as SubViewport
	var front := world.get_node_or_null(^"WorldFront") as SubViewport
	assert_not_null(back, "the base scene carries WorldBack")
	assert_not_null(front, "the base scene carries WorldFront")
	if back == null or front == null:
		return
	assert_eq(back.render_target_update_mode, SubViewport.UPDATE_DISABLED, "fresh world: back asleep")
	assert_eq(front.render_target_update_mode, SubViewport.UPDATE_DISABLED, "fresh world: front asleep")
	# Far off any view, so nothing but the notifier below can wake it.
	var holder := world.add_rig(Gimbal3D.new(), Vector2(1e6, 1e6), 32.0)
	assert_eq(world.visible_rig_count(), 0, "a rig nobody sees does not count")
	assert_eq(back.render_target_update_mode, SubViewport.UPDATE_DISABLED, "an off-screen rig keeps it asleep")
	var notifier := holder.get_node_or_null(^"OnScreen") as VisibleOnScreenNotifier3D
	assert_not_null(notifier, "add_rig gives the holder an OnScreen notifier")
	if notifier == null:
		return
	notifier.screen_entered.emit()
	assert_eq(world.visible_rig_count(), 1, "the notifier reporting on-screen counts the rig")
	assert_eq(back.render_target_update_mode, SubViewport.UPDATE_ALWAYS, "one rig on screen: back renders")
	assert_eq(front.render_target_update_mode, SubViewport.UPDATE_ALWAYS, "one rig on screen: front renders")
	holder.free()
	assert_eq(world.visible_rig_count(), 0, "a freed holder no longer counts")
	assert_eq(back.render_target_update_mode, SubViewport.UPDATE_DISABLED, "freed: back asleep again")
	assert_eq(front.render_target_update_mode, SubViewport.UPDATE_DISABLED, "freed: front asleep again")


func test_world_scene_is_the_two_camera_split() -> void:
	var world: GimbalWorld = (load(GimbalWorld.SCENE) as PackedScene).instantiate()
	add_child_autofree(world)
	assert_false("split" in world, "one implementation of the contract: no split flag")
	assert_null(world.find_child("Occluder*", true, false), "no occluder anywhere")
	var back := world.get_node_or_null(^"WorldBack") as SubViewport
	var front := world.get_node_or_null(^"WorldFront") as SubViewport
	assert_not_null(back, "WorldBack exists")
	assert_not_null(front, "WorldFront exists")
	if back == null or front == null:
		return
	assert_eq(front.world_3d, back.find_world_3d(), "the front viewport draws the back's World3D")
	assert_eq(back.msaa_3d, Viewport.MSAA_4X, "back is 4x MSAA")
	assert_eq(front.msaa_3d, Viewport.MSAA_4X, "front is 4x MSAA")
	var cam_back := back.get_camera_3d()
	var cam_front := front.get_camera_3d()
	assert_not_null(cam_back, "back has a camera")
	assert_not_null(cam_front, "front has a camera")
	if cam_back == null or cam_front == null:
		return
	var bp := GimbalWorld.clip_planes(false)
	var fp := GimbalWorld.clip_planes(true)
	assert_almost_eq(cam_back.near, bp.x, 0.001, "back near = clip_planes(false).x")
	assert_almost_eq(cam_back.far, bp.y, 0.001, "back far = clip_planes(false).y")
	assert_almost_eq(cam_front.near, fp.x, 0.001, "front near = clip_planes(true).x")
	assert_almost_eq(cam_front.far, fp.y, 0.001, "front far = clip_planes(true).y")


# The editor gate: a world is live anywhere at runtime, and in the editor only
# outside the scene being edited (the sandbox panel's own tree).
func test_edited_scene_membership_is_the_root_and_its_descendants() -> void:
	var root := Node2D.new()
	var child := Node2D.new()
	var outside := Node2D.new()
	root.add_child(child)
	autofree(root)
	autofree(outside)
	assert_true(GimbalWorld.in_edited_scene(root, root), "the edited root itself")
	assert_true(GimbalWorld.in_edited_scene(child, root), "a node inside the edited scene")
	assert_false(GimbalWorld.in_edited_scene(outside, root), "a node outside it (the panel)")
	assert_false(GimbalWorld.in_edited_scene(child, null), "no scene open")


func test_runtime_is_always_live() -> void:
	var node := Node2D.new()
	add_child_autofree(node)
	assert_true(GimbalWorld.is_live_for(node), "outside the editor every node may hold a world")
