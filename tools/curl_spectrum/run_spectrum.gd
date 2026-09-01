extends SceneTree

## #705's entry point. Run via:
##
##     mise run curl-spectrum                       # default sweep + snapshot
##     mise run curl-spectrum -- 800 5 6            # node_count, seeds, targets/map
##
## Dynamic `load()` rather than a top-level `preload`, for the reason
## `tools/balance/run_balance.gd` documents at length: `--script` compiles this
## file and everything it statically references BEFORE the project's autoloads
## exist, and the cast probe transitively pulls in [Entity], which names them.

const _DEFAULT_NODE_COUNT := 300
const _DEFAULT_SEEDS := 3
const _DEFAULT_TARGETS := 4


func _initialize() -> void:
	call_deferred("_start")


func _start() -> void:
	await process_frame
	await process_frame
	var args := OS.get_cmdline_user_args()
	var node_count := int(args[0]) if args.size() > 0 else _DEFAULT_NODE_COUNT
	var seeds := int(args[1]) if args.size() > 1 else _DEFAULT_SEEDS
	var targets := int(args[2]) if args.size() > 2 else _DEFAULT_TARGETS
	var harness = load("res://tools/curl_spectrum/spectrum_harness.gd")
	var report = load("res://tools/curl_spectrum/spectrum_report.gd")
	var started := Time.get_ticks_msec()
	var result: Dictionary = harness.run(root, node_count, seeds, targets)
	print(report.format(result))
	report.write_snapshot(result)
	print("\n✓ snapshot written to %s (%.1fs)"
			% [harness.SNAPSHOT_PATH, 0.001 * float(Time.get_ticks_msec() - started)])
	await process_frame
	quit(0)
