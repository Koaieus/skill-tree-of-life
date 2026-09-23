extends GutTest

## [TweenClock] — the tween consumer's step-by-hand door (#992). Pending until
## the first consumer lands (#1068); the drone's first commit flips these RED.
##
## Contract, proven by the 2026-09-23 spike (a paused Tween on an in-tree node
## steps property, interval and callback in order through `custom_step`, and
## two real frames later nothing has moved):
##   * manual=false → `tween(host)` is a running tween, indistinguishable from
##     `host.create_tween()`.
##   * manual=true → the tween is paused at birth; `advance(d)` steps it by d.
##   * `advance` fires `tween_callback` at the exact stepped instant, once.
##   * finished / killed tweens are pruned; `advance` on an empty clock is free.
##   * `kill_all` leaves no live tween.


func test_manual_false_hands_out_a_running_tween() -> void:
	pending("stub on master — flipped RED by #1068")


func test_manual_true_creates_the_tween_paused_and_two_real_frames_move_nothing() -> void:
	pending("stub on master — flipped RED by #1068")


func test_advance_steps_property_then_interval_then_callback_in_order() -> void:
	pending("stub on master — flipped RED by #1068")


func test_a_finished_tween_is_pruned_and_a_killed_one_is_skipped() -> void:
	pending("stub on master — flipped RED by #1068")


func test_kill_all_leaves_nothing_live() -> void:
	pending("stub on master — flipped RED by #1068")
