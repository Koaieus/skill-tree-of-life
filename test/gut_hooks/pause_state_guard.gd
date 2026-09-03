class_name PauseStateGuard

## Suite-level guard for #737 — a leaked `get_tree().paused` is sticky
## SceneTree state that outlives the script that set it, and GUT does not
## reset it between scripts. `ui/pause_menu.gd`'s `_toggle` is the only writer
## in the repo, so any test that mounts a `HudRoot`/`GameRoot` and flips the
## pause menu active without restoring it (`after_each`/`after_all`) leaks it
## into every script that runs after.
##
## The failure mode this exists to catch: `get_tree().create_timer(...)`
## defaults to `process_always = true` and keeps firing while paused, but a
## `Tween` from `create_tween()` defaults to `TWEEN_PAUSE_BOUND` and silently
## STOPS while paused — so a tween-sampling test downstream fails with "the
## value never moved", reading like a bug in the code under test rather than
## in an unrelated earlier script.
##
## Wired in as GUT's `pre_run_script` (`.gutconfig.json`) via
## `pause_leak_pre_run_hook.gd`, which connects this to GUT's own
## `start_script` / `end_script` signals — so it runs once per script,
## globally, with zero edits to any of the ~400 existing test files and zero
## changes to `addons/gut/` itself (a subclass overriding `before_each`/
## `after_each` does not chain to a base implementation in GDScript, so
## patching `GutTest` would give order-dependent, incomplete coverage).
##
## Kept as this separate, signal-free class so the attribution logic is
## unit-testable directly against a fake `CollectedScript`/`CollectedTest`
## pair — see `test/unit/test_pause_state_guard.gd`. A real leaking fixture
## living in the GUT-discovered `test/unit/` tree would poison every script
## that ran after it on every future `mise run test`, so it is deliberately
## not exercised end-to-end that way.


## Builds the failure message naming the leaking script.
static func build_message(script_full_name: String) -> String:
	return (
		"Suite-level guard (#737): %s left get_tree().paused == true when it finished. "
		% script_full_name
		+ "That leaks into every script that runs after it in the same suite run — "
		+ "a Tween-driven test downstream would silently stop advancing and look "
		+ "broken instead. The leaking script (or one of its tests) flips "
		+ "PauseMenu.active / get_tree().paused without restoring it in "
		+ "after_each/after_all."
	)


## Attributes a leak to `coll_script` (a GUT `CollectedScript`) by failing its
## last real test. Real tests are what GUT exports to JUnit XML; `before_all`/
## `after_all` pseudo-tests are tracked separately (`setup_teardown_tests`)
## and are NOT exported — failing one of those would show in the console/log
## but not flip `mise run test`'s verdict.
##
## Returns true if the failure was attributed to a real test, false if the
## script had none to blame (the caller should fall back to logging).
static func report_leak(coll_script, script_full_name: String) -> bool:
	if coll_script == null or coll_script.tests.is_empty():
		return false
	coll_script.tests[-1].add_fail(build_message(script_full_name))
	return true
