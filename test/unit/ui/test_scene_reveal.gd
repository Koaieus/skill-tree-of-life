extends GutTest

## The curtain contract between [SceneTransition], [SceneDirector] and [GameRoot].
##
## The bug: `fade_out` used to `hide()` the whole curtain the moment it finished,
## so a lobby START played a half-second fade to black, uncovered the outgoing
## menu for the threaded load, and then uncovered the INCOMING level one frame
## after the scene swap — while `_setup_level` was still generating. What the
## player saw was a progress bar flashing at 0%, the HUD alone over an empty
## world, and the world appearing all at once.
##
## Three halves hold the fix and each is pinned below: the curtain stays up
## between the two fades, the bar appears only when something reports progress,
## and a [GameRoot] does not call itself presentable until `_ready` is done.


func before_each() -> void:
	# Another suite that froze a level mid-fade can leave the autoload covered;
	# these assertions are about the curtain, so they start from a known one.
	_reset_curtain()


func after_each() -> void:
	# SceneTransition is an autoload — never leave the suite behind a black
	# rect, whatever an assertion did.
	_reset_curtain()


func _reset_curtain() -> void:
	SceneTransition.anim.stop()
	SceneTransition.set_faded(false)
	SceneTransition.progress_bar.hide()
	SceneTransition.hide()


func test_fade_out_leaves_the_curtain_up() -> void:
	await SceneTransition.fade_out()
	assert_true(SceneTransition.visible, "the layer stays shown after fading out")
	assert_true(SceneTransition.is_curtain_up(),
			"the screen stays covered until someone fades back in — "
			+ "this is the whole fix; a hide() here is the flash")


func test_the_progress_bar_waits_for_a_reporter() -> void:
	await SceneTransition.fade_out()
	assert_false(SceneTransition.progress_bar.visible,
			"no bar until something actually reports progress — a bar sitting "
			+ "at 0%% for the length of a fade is what read as a glitch")
	SceneTransition.progress_bar.show()
	SceneTransition.set_progress(42.0)
	assert_eq(SceneTransition.progress_bar.value, 42.0,
			"set_progress speaks the bar's own 0..100 units")


func test_fade_in_lowers_the_curtain_and_the_bar() -> void:
	await SceneTransition.fade_out()
	SceneTransition.progress_bar.show()
	await SceneTransition.fade_in()
	assert_false(SceneTransition.is_curtain_up(), "the screen is uncovered")
	assert_false(SceneTransition.progress_bar.visible, "the bar goes with it")


func test_an_untouched_curtain_is_not_up() -> void:
	# The guard that keeps a directly-launched sandbox (nobody faded out) from
	# gaining a black fade-in nobody asked for.
	assert_false(SceneTransition.is_curtain_up())


func test_a_game_root_is_not_presentable_until_ready_finishes() -> void:
	var root: GameRoot = preload("res://scenes/game_root.tscn").instantiate()
	root.auto_start_turn = false
	assert_true(root.has_method("is_reveal_ready"),
			"the method name SceneDirector probes for")
	assert_false(root.is_reveal_ready(), "not before it is even in the tree")
	add_child_autofree(root)
	# `_ready` is a coroutine (it awaits `_setup_level`, and a layout frame
	# after composing the HUD), so readiness is not same-frame.
	for _i in 10:
		await get_tree().process_frame
	assert_true(root.is_reveal_ready(), "presentable once _ready has run through")
