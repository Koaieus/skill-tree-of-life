extends GutTest

## EndTurnButton confirm-bubble auto-dismiss (#90). The bubble used to stay open
## forever; it now auto-hides via a scene-authored one-shot %ConfirmTimer (and the
## button's focus_exited), both wired to hide_confirm in the .tscn.
##
## This also serves as a scene-load smoke: hand-authored .tscn breakage (bad UID /
## stripped field / mistyped connection target) fails SILENTLY in Godot — no parse
## error — so instantiating the scene and asserting the wiring is the only guard.

const _SCENE := preload("res://ui/end_turn_button/end_turn_button.tscn")

var _btn: EndTurnButton


func before_each() -> void:
	_btn = _SCENE.instantiate() as EndTurnButton
	add_child(_btn)
	await get_tree().process_frame  # _ready + @onready resolution


func after_each() -> void:
	_btn.queue_free()


func test_scene_loads_and_timer_resolves() -> void:
	assert_not_null(_btn, "scene should instantiate as EndTurnButton")
	# %ConfirmTimer must resolve — proves the hand-authored Timer node + unique
	# name survived and the script's @onready binds it.
	var timer := _btn.get_node_or_null("%ConfirmTimer")
	assert_not_null(timer, "%ConfirmTimer node should exist in the scene")
	assert_true(timer is Timer, "ConfirmTimer should be a Timer")
	assert_true((timer as Timer).one_shot, "auto-dismiss timer must be one-shot")


func test_show_confirm_starts_the_timer() -> void:
	var timer := _btn.get_node("%ConfirmTimer") as Timer
	assert_true(timer.is_stopped(), "timer idle before show")
	_btn.show_confirm("you still have action points")
	assert_true(_btn.is_confirm_open(), "bubble should be visible after show_confirm")
	assert_false(timer.is_stopped(), "show_confirm must start the auto-dismiss countdown")


func test_hide_confirm_stops_the_timer() -> void:
	var timer := _btn.get_node("%ConfirmTimer") as Timer
	_btn.show_confirm("x")
	_btn.hide_confirm()
	assert_false(_btn.is_confirm_open(), "bubble hidden after hide_confirm")
	assert_true(timer.is_stopped(), "hide_confirm must stop the countdown")


func test_timeout_hides_the_bubble() -> void:
	# Fire the timer's timeout directly (no 4s wait) — proves timeout → hide_confirm.
	_btn.show_confirm("x")
	assert_true(_btn.is_confirm_open())
	(_btn.get_node("%ConfirmTimer") as Timer).timeout.emit()
	assert_false(_btn.is_confirm_open(), "timeout should dismiss the bubble")
