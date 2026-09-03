extends GutTest

## #737 — the suite-level guard against a leaked `get_tree().paused`.
##
## Two layers, two kinds of proof:
##
## - [PauseStateGuard] itself is signal-free and pure, tested directly against
##   real GUT `CollectedScript`/`CollectedTest` objects (the same classes GUT
##   builds at collection time) rather than hand-rolled fakes.
## - `pause_leak_pre_run_hook.gd` is the wiring that connects it to GUT's own
##   `start_script`/`end_script` signals; exercised here against a small stub
##   standing in for the live `GutMain` instance (`_FakeGut`).
##
## [b]`_FakeGut.get_tree()` returns a `_FakeTree` stub, never the real
## `get_tree()`.[/b] An earlier version of this file pinned `get_tree().paused`
## on the ACTUAL SceneTree this suite is running in to simulate the leak —
## that hung the whole GUT process (killed after ~6 minutes at ~0% CPU,
## presumably GUT's own timer/paint machinery deadlocking against its own
## paused tree). The hook only ever reads/writes `tree.paused` through
## whatever `gut.get_tree()` hands back, so a duck-typed stand-in proves the
## same wiring with zero risk to the runner hosting the test.
##
## No real leaking fixture lives in the discovered `test/unit/` tree either —
## that would poison every script after it on every future `mise run test`.

const _PRE_RUN_HOOK := preload("res://test/gut_hooks/pause_leak_pre_run_hook.gd")


class _FakeTree:
	var paused: bool = false


class _FakeLogger:
	var errors: Array[String] = []

	func error(text: String) -> void:
		errors.append(text)


class _FakeGut:
	signal start_script(coll_script)
	signal end_script

	var logger := _FakeLogger.new()
	var tree := _FakeTree.new()

	func get_tree() -> _FakeTree:
		return tree


func _script_with_one_test(path: String, test_name: String = "test_something") -> Object:
	var coll_script = GutUtils.CollectedScript.new()
	coll_script.path = path
	var t = GutUtils.CollectedTest.new()
	t.name = test_name
	t.add_pass("sanity — the test itself passed")
	coll_script.tests = [t]
	return coll_script


func _installed_hook() -> Dictionary:
	var hook = _PRE_RUN_HOOK.new()
	var fake_gut := _FakeGut.new()
	hook.gut = fake_gut
	hook.run()
	return {"hook": hook, "gut": fake_gut}


# --- PauseStateGuard, direct -------------------------------------------------

func test_report_leak_fails_the_last_real_test() -> void:
	var coll_script = _script_with_one_test("res://test/unit/test_fake_leaker.gd")

	var attributed := PauseStateGuard.report_leak(coll_script, coll_script.get_full_name())

	assert_true(attributed, "a script with a real test must be attributable")
	assert_true(coll_script.tests[-1].is_failing(),
			"the last real test must now read as failed")


func test_report_leak_names_the_leaking_script_in_the_message() -> void:
	var coll_script = _script_with_one_test("res://test/unit/test_fake_leaker.gd")

	PauseStateGuard.report_leak(coll_script, coll_script.get_full_name())

	assert_string_contains(coll_script.tests[-1].fail_texts[-1],
			"test_fake_leaker.gd")
	assert_string_contains(coll_script.tests[-1].fail_texts[-1], "get_tree().paused")


func test_report_leak_only_touches_the_last_test_not_earlier_ones() -> void:
	var coll_script = GutUtils.CollectedScript.new()
	coll_script.path = "res://test/unit/test_fake_leaker.gd"
	var first = GutUtils.CollectedTest.new()
	first.name = "test_first"
	first.add_pass("sanity")
	var last = GutUtils.CollectedTest.new()
	last.name = "test_last"
	last.add_pass("sanity")
	coll_script.tests = [first, last]

	PauseStateGuard.report_leak(coll_script, coll_script.get_full_name())

	assert_false(first.is_failing(), "an innocent earlier test must not be blamed")
	assert_true(last.is_failing())


func test_report_leak_with_no_real_tests_cannot_attribute() -> void:
	var coll_script = GutUtils.CollectedScript.new()
	coll_script.path = "res://test/unit/test_fake_leaker.gd"
	coll_script.tests = []

	var attributed := PauseStateGuard.report_leak(coll_script, coll_script.get_full_name())

	assert_false(attributed,
			"a script with nothing to fail must signal the caller to fall back")


# --- the hook's wiring, end to end (against a stub GutMain) -----------------

func test_hook_fails_the_finished_script_and_clears_the_flag_when_it_leaked() -> void:
	var rig := _installed_hook()
	var fake_gut: _FakeGut = rig.gut

	var coll_script = _script_with_one_test("res://test/unit/test_fake_leaker.gd")
	fake_gut.start_script.emit(coll_script)
	fake_gut.tree.paused = true  # the leak the guard exists to catch
	fake_gut.end_script.emit()

	assert_false(fake_gut.tree.paused,
			"the guard must clear the flag or every downstream script gets mislabeled")
	assert_true(coll_script.tests[-1].is_failing(),
			"end_script must reach PauseStateGuard.report_leak for the script that just ran")
	assert_string_contains(coll_script.tests[-1].fail_texts[-1], "test_fake_leaker.gd")


func test_hook_does_nothing_when_the_script_did_not_leak() -> void:
	var rig := _installed_hook()
	var fake_gut: _FakeGut = rig.gut

	var coll_script = _script_with_one_test("res://test/unit/test_clean.gd")
	fake_gut.start_script.emit(coll_script)
	fake_gut.end_script.emit()

	assert_false(coll_script.tests[-1].is_failing(), "a clean script must stay clean")
	assert_true(fake_gut.logger.errors.is_empty())


func test_hook_falls_back_to_logging_when_the_leaking_script_has_no_real_tests() -> void:
	var rig := _installed_hook()
	var fake_gut: _FakeGut = rig.gut

	var coll_script = GutUtils.CollectedScript.new()
	coll_script.path = "res://test/unit/test_before_all_only.gd"
	coll_script.tests = []

	fake_gut.start_script.emit(coll_script)
	fake_gut.tree.paused = true
	fake_gut.end_script.emit()

	assert_false(fake_gut.tree.paused, "still reset, even when nothing can be blamed directly")
	assert_eq(fake_gut.logger.errors.size(), 1)
	assert_string_contains(fake_gut.logger.errors[0], "test_before_all_only.gd")
