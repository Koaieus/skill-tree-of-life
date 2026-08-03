extends SceneTree

## Full balance table (#268). Run via:
##
##     mise run balance
##     godot --headless --path . --script res://tools/balance/run_balance.gd
##
## AMENDMENT (2026-08-03): this harness is INFORMATIVE, never binding — always
## exits 0. A non-zero exit is reserved for the harness itself crashing, never
## for an `OUT` invariant reading.
##
## Dynamic `load()`, never a top-level `preload`/global-class reference:
## `--script` mode compiles the requested script (and everything it statically
## references) BEFORE the project's autoloads (`Events`, `StatRegistry`, ...)
## are added to the tree — verified empirically. `balance_harness.gd`
## transitively pulls in `Entity`, which references those autoloads by bare
## identifier at compile time, so a `const := preload(...)`/typed reference to
## it here would fail to compile before the tree even starts. Deferring past a
## couple of frames, then `load()`-ing at runtime, sidesteps the ordering
## entirely — by then the autoloads are live tree children.


func _initialize() -> void:
	call_deferred("_start")


func _start() -> void:
	await process_frame
	await process_frame
	_run()


func _run() -> void:
	var harness = load("res://tools/balance/balance_harness.gd")
	var result: Dictionary = await harness.run(root)
	var table: String = harness.format_table(result)
	print(table)
	harness.write_snapshot(result)
	print("✓ snapshot written to %s" % harness.SNAPSHOT_PATH)
	# Give every fixture's queue_free() (queued by BalanceScenarios.free_fixture,
	# never called immediately) a frame to actually run before the process
	# exits — otherwise they're still pending and print as leaked at exit.
	await process_frame
	quit(0)
