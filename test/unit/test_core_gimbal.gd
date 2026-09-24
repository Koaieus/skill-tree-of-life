extends GutTest
## CoreGimbal (#1108): the entity look worn in a CorePresence slot — one
## Gimbal3D rig in the viewport's GimbalWorld, identity in, rings/phase derived
## from the SkillNodeVisual identity contract, gated like CoreHalos.

const _GIMBAL := preload("res://skill_node/visuals/core_gimbal.tscn")
const _TINT := Color(0.9, 0.3, 0.2)
const _RADIUS := 30.0

var _host: Node2D


func _make(at := Vector2.ZERO) -> Node2D:
	_host = Node2D.new()
	_host.position = at
	add_child_autofree(_host)
	var leaf: Node2D = _GIMBAL.instantiate()
	leaf.entity_tint = _TINT
	leaf.configure(_RADIUS)
	_host.add_child(leaf)
	await get_tree().process_frame
	return leaf


func test_leaf_acquires_one_rig_and_pushes_identity() -> void:
	var leaf := await _make()
	var world := GimbalWorld.acquire(leaf)
	assert_eq(world.rig_count(), 1, "one rig in the viewport's GimbalWorld")
	var rig: Gimbal3D = leaf._rig
	assert_not_null(rig, "the leaf holds its rig")
	if rig == null:
		return
	assert_eq(rig.tint, _TINT, "tint is the entity tint")
	assert_eq(rig.ring_count, leaf.ring_count, "ring_count pushed")
	assert_almost_eq(rig.phase, leaf.phase, 1e-5, "phase pushed")
	assert_eq(rig.style, Gimbal3D.Style.HOLO_GLASS, "the entity look is holo glass")
	assert_almost_eq(rig.base_radius, _RADIUS * leaf.halo_scale * 1.434, 1e-3,
		"base_radius = radius * halo_scale * the cpu2d footprint constant")
	_host.remove_child(leaf)
	await get_tree().process_frame
	assert_eq(world.rig_count(), 0, "leaving the tree frees the holder")
	leaf.free()


func test_gate_mirrors_the_rig_visibility() -> void:
	var leaf := await _make()
	var rig: Gimbal3D = leaf._rig
	assert_not_null(rig)
	if rig == null:
		return
	leaf.hide()
	assert_false(rig.visible, "hidden in tree -> rig hidden")
	leaf.show()
	leaf.revealed = false
	assert_false(rig.visible, "unrevealed with the notifier silent -> rig hidden")
	leaf.revealed = true
	assert_true(rig.visible, "revealed -> rig shown")


func test_travel_glide_moves_the_holder() -> void:
	var leaf := await _make(Vector2(100, 50))
	assert_not_null(leaf._holder)
	if leaf._holder == null:
		return
	leaf.on_core_travel_start(Vector2(40, 0), 0.05)
	assert_almost_eq(leaf._holder.position.x, 140.0, 0.01, "the holder starts at the old node")
	await get_tree().create_timer(0.15).timeout
	assert_true(leaf._holder.position.is_equal_approx(GimbalWorld.to_world_3d(leaf.global_position)),
		"after the tween the holder sits on the node")
	assert_true(leaf.global_position.is_equal_approx(Vector2(100, 50)))


func test_rings_and_phase_derive_from_identity() -> void:
	var leaf: Node2D = autofree(_GIMBAL.instantiate())
	leaf.owner_level = 25
	assert_eq(leaf.ring_count, 4, "level 25 -> 4 rings")
	leaf.owner_level = 30
	assert_eq(leaf.ring_count, 5, "level 30 -> 5 rings")
	leaf.node_seed = 7
	assert_almost_eq(leaf.phase, wrapf(7 * 2.399963, 0.0, TAU), 1e-5, "phase is the golden-angle wrap")
	for m in (CorePresence as Script).get_script_method_list():
		var n := String(m["name"])
		assert_false(n.contains("ring") or n.contains("phase"),
			"CorePresence never names rings or phase (%s)" % n)
