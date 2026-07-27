extends GutTest

## Toaster PLACEMENT regressions — two bugs that both read as "the toast shows
## up somewhere else entirely":
##
## 1. `floater_toaster.tscn` shipped a stale editor `position = (304, 208)` on
##    its root. Every path that sets the toaster's position after add_child
##    (the manager) overwrote it, so gameplay hid the bug — but [ToastCell]
##    parents a toaster to a centered anchor and sets nothing, which put the
##    stack in the cell's bottom-right corner, mostly out of view.
## 2. The manager copied `anchor.global_position` verbatim. For a HUD anchor
##    (Hero Sigil Card, under the UI CanvasLayer) that is a *screen* coordinate
##    being written into a *world*-space node, so player toasts drifted by the
##    whole camera transform.

const _TOASTER_SCENE := preload("res://ui/floating_number_layer/floater_toaster.tscn")
const _MANAGER_SCENE := preload("res://ui/floating_number_layer/floater_director.tscn")

var _manager: FloaterToasterManager


func before_each() -> void:
	var director := _MANAGER_SCENE.instantiate() as FloaterDirector
	director.vision_system = null
	add_child_autofree(director)
	_manager = director.renderer


func after_each() -> void:
	# The canvas transform lives on the shared test viewport — reset it or the
	# skew leaks into every later test in the run.
	get_viewport().canvas_transform = Transform2D()


func _spawn_at(target: Node2D) -> FloaterToaster:
	var req := FloaterRequest.new()
	req.target = target
	req.text = "+5 XP"
	req.style = FloaterStyle.new()
	_manager.spawn(req)
	for c in _manager.get_children():
		if c is FloaterToaster:
			return c
	return null


func test_scene_root_carries_no_baked_offset() -> void:
	var toaster := _TOASTER_SCENE.instantiate() as FloaterToaster
	add_child_autofree(toaster)
	assert_eq(toaster.position, Vector2.ZERO,
			"a bare toaster sits on its parent's origin (ToastCell relies on this)")


func test_world_anchor_placement_is_identity_under_a_camera_transform() -> void:
	# Emulate a camera that has panned and zoomed.
	get_viewport().canvas_transform = Transform2D(0.0, Vector2(2.0, 2.0), 0.0, Vector2(-800, -600))
	var target := Node2D.new()
	add_child_autofree(target)
	target.global_position = Vector2(123, 45)

	var toaster := _spawn_at(target)
	assert_not_null(toaster)
	assert_almost_eq(toaster.global_position.x, 123.0, 0.01, "world anchor round-trips exactly")
	assert_almost_eq(toaster.global_position.y, 45.0, 0.01, "world anchor round-trips exactly")


func test_hud_anchor_is_converted_out_of_its_canvas_layer() -> void:
	var canvas_xform := Transform2D(0.0, Vector2(2.0, 2.0), 0.0, Vector2(-800, -600))
	get_viewport().canvas_transform = canvas_xform

	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var hud_anchor := Node2D.new()
	layer.add_child(hud_anchor)
	hud_anchor.position = Vector2(300, 200)  # screen pixels, NOT world

	var toaster := _spawn_at(hud_anchor)
	assert_not_null(toaster)
	# Where the toaster must sit in world space to *render* on that screen pixel.
	var expected := canvas_xform.affine_inverse() * Vector2(300, 200)
	assert_almost_eq(toaster.global_position.x, expected.x, 0.01, "HUD anchor mapped through the camera")
	assert_almost_eq(toaster.global_position.y, expected.y, 0.01, "HUD anchor mapped through the camera")
	assert_ne(toaster.global_position, Vector2(300, 200),
			"the raw screen coordinate is NOT a valid world position here")
