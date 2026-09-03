extends GutHookScript

## Installs the #737 suite-level guard. Configured as GUT's `pre_run_script`
## in `.gutconfig.json`, which runs this `run()` once, before any script
## executes — the sanctioned place to hang a cross-cutting concern off GUT's
## own `start_script(coll_script)` / `end_script` signals (both already
## emitted once per test script, regardless of what that script overrides).
##
## All attribution logic lives in the signal-free `PauseStateGuard`
## (unit-tested); this file is just the wiring, which is not itself
## unit-testable without a live GUT run.

## The script GUT is currently running, captured on `start_script` so
## `end_script` (which carries no arguments) knows who to blame.
var _running_script = null


func run() -> void:
	gut.start_script.connect(_on_start_script)
	gut.end_script.connect(_on_end_script)


func _on_start_script(coll_script) -> void:
	_running_script = coll_script


func _on_end_script() -> void:
	# `gut` is an untyped GutHookScript field (real GutMain in production, a
	# duck-typed stub in tests) — `:=` cannot infer a type from a call through
	# it, which is a *parse* error GUT then reports as a hook load failure. It
	# aborts every script the suite has, but that abort path never reaches
	# GUT's own quit() — the process spins printing FPS forever instead of
	# exiting, which looks exactly like a hang. Annotate explicitly instead.
	var tree: Object = gut.get_tree()
	if tree != null and tree.paused:
		var script_name := "<unknown script>"
		if _running_script != null:
			script_name = _running_script.get_full_name()
		if not PauseStateGuard.report_leak(_running_script, script_name):
			gut.logger.error(PauseStateGuard.build_message(script_name))
		# Reset regardless of attribution — leaving it true would mislabel
		# every downstream script as the leaker instead of just this one.
		tree.paused = false
	_running_script = null
