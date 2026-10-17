extends GutTest

## The mouse pick area is a padded ring OUTSIDE the gameplay hitbox: the root
## Area2D's shape is what blades, gathers and defender zones query, so it
## stays at `radius`, while `PickArea` alone carries hover and click at
## `radius + pick_padding` on its own layer. Padded rings of neighbours can
## overlap, so exactly one node owns the hover at a time — the one whose rim
## is nearest the cursor — and only the owner takes a click.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")

var _a: SkillNode
var _b: SkillNode
var _hovered: Array = []
var _unhovers: int = 0


func before_each() -> void:
	_a = _SKILL_NODE_SCENE.instantiate()
	_b = _SKILL_NODE_SCENE.instantiate()
	add_child(_a)
	add_child(_b)
	_hovered.clear()
	_unhovers = 0
	Events.skill_node_hovered.connect(_on_hovered)
	Events.skill_node_unhovered.connect(_on_unhovered)


func after_each() -> void:
	Events.skill_node_hovered.disconnect(_on_hovered)
	Events.skill_node_unhovered.disconnect(_on_unhovered)
	for n in [_a, _b]:
		if is_instance_valid(n):
			n.free()


func _on_hovered(node: SkillNode) -> void:
	_hovered.append(node)


func _on_unhovered() -> void:
	_unhovers += 1


func _pick_shape(node: SkillNode) -> CircleShape2D:
	return node.get_node(^"PickArea/Shape").shape as CircleShape2D


func _motion(at: Vector2) -> InputEventMouseMotion:
	var mm := InputEventMouseMotion.new()
	mm.global_position = at
	mm.position = at
	return mm


func _press(at: Vector2) -> InputEventMouseButton:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = at
	mb.global_position = at
	return mb


func test_pick_ring_is_padded_and_the_hitbox_is_not() -> void:
	var hit := _a.get_node(^"CollisionShape2D").shape as CircleShape2D
	assert_almost_eq(hit.radius, _a.radius, 0.001, "the gameplay hitbox stays at radius")
	assert_almost_eq(_pick_shape(_a).radius, _a.radius + _a.pick_padding, 0.001,
			"the pick ring is radius + pick_padding")
	assert_gt(_a.pick_padding, 0.0, "the default actually pads")


func test_pick_ring_follows_a_radius_change() -> void:
	_a.base_radius += 10.0
	assert_almost_eq(_pick_shape(_a).radius, _a.radius + _a.pick_padding, 0.001)
	assert_ne(_pick_shape(_a), _pick_shape(_b), "each instance owns its pick shape")


func test_only_the_pick_area_is_mouse_pickable() -> void:
	assert_false(_a.input_pickable, "the hitbox root no longer picks")
	var pick := _a.get_node(^"PickArea") as Area2D
	assert_true(pick.input_pickable)
	assert_eq(pick.collision_layer, 1 << (SkillNode.PICK_COLLISION_LAYER - 1),
			"the pick ring is on its own layer only, never layer 1")
	assert_eq(pick.collision_mask, 0)


func test_overlap_hover_goes_to_the_nearest_rim_and_a_stale_exit_is_silent() -> void:
	_a.position = Vector2.ZERO
	_b.position = Vector2(_a.radius + _b.radius + _a.pick_padding, 0.0)
	var between := Vector2(_a.radius + _a.pick_padding * 0.75, 0.0)  # nearer B's rim

	_a._on_pick_mouse_entered()
	assert_eq(_hovered, [_a], "entering A's ring hovers A")
	_b._on_pick_mouse_entered()
	_b._on_pick_input_event(null, _motion(between), 0)
	assert_eq(_hovered.back(), _b, "B's rim is nearer the cursor: B takes the hover")
	assert_false(_a.hover_ring.visible, "only the owner shows its ring")
	assert_true(_b.hover_ring.visible)

	_a._on_pick_mouse_exited()
	assert_eq(_unhovers, 0, "leaving A while B owns the hover must not clear it")

	_b._on_pick_mouse_exited()
	assert_eq(_unhovers, 1, "the owner leaving clears the hover")


func test_only_the_hover_owner_takes_a_click() -> void:
	_a.position = Vector2.ZERO
	_b.position = Vector2(_a.radius + _b.radius + _a.pick_padding, 0.0)
	var at := Vector2(_a.radius + 1.0, 0.0)
	_a._on_pick_mouse_entered()
	_b._on_pick_mouse_entered()
	_a._on_pick_input_event(null, _motion(at), 0)
	_b._on_pick_input_event(null, _motion(at), 0)
	watch_signals(_a)
	watch_signals(_b)
	_a._on_pick_input_event(null, _press(at), 0)
	_b._on_pick_input_event(null, _press(at), 0)
	assert_signal_emit_count(_a, "left_clicked", 1, "the owner takes the click")
	assert_signal_emit_count(_b, "left_clicked", 0, "an overlapped non-owner does not")
