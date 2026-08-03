class_name BalanceHarness
extends RefCounted

## Entry point for the #268 balance harness: runs every scenario fixture,
## checks the (all-`TBD`) ratio invariants, and formats/writes the result.
## See `tools/balance/README.md` for the informative-only contract this whole
## tool operates under.

const SNAPSHOT_PATH := "res://tools/balance/snapshot.md"

const _HEADER_NOTE := "Informative only — an order-of-magnitude smell test for runaway or non-fun values. Not a source of truth and never a build gate."


## Coroutine — `root` is anything with `get_tree()` already in the SceneTree
## (the harness scripts pass their own `root`; the GUT test passes `self`).
static func run(root: Node) -> Dictionary:
	var scenarios := await BalanceScenarios.run_all(root)
	var invariants := BalanceInvariants.check(scenarios)
	return {
		"scenarios": scenarios,
		"invariants": invariants,
		"generated_at": Time.get_datetime_string_from_system(true),
	}


static func format_table(result: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("# Balance Harness Snapshot")
	lines.append("")
	lines.append("> %s" % _HEADER_NOTE)
	lines.append("> See `tools/balance/README.md` — including why this snapshot goes stale")
	lines.append("> once #274 lands.")
	lines.append("")
	lines.append("Generated: %s" % str(result.get("generated_at", "?")))
	lines.append("")

	for s in result["scenarios"]:
		lines.append("## %s" % s["name"])
		lines.append("")
		lines.append("| Readout | Value |")
		lines.append("|---|---|")
		var readouts: Dictionary = s["readouts"]
		var keys := readouts.keys()
		keys.sort()
		for k in keys:
			lines.append("| %s | %s |" % [k, _fmt_value(readouts[k])])
		lines.append("")

	lines.append("## Invariants")
	lines.append("")
	lines.append("_Every range ships `TBD` (D-13 — an implementing agent must never invent")
	lines.append("balance ranges). `OUT` is a printed observation, exactly like `TBD` — it never_")
	lines.append("_fails this run._")
	lines.append("")
	lines.append("| Invariant | Status | Detail | Why |")
	lines.append("|---|---|---|---|")
	for inv in result["invariants"]:
		lines.append("| %s | %s | %s | %s |" % [inv["name"], inv["status"], inv["detail"], inv["why"]])
	lines.append("")

	return "\n".join(lines)


static func write_snapshot(result: Dictionary, path: String = SNAPSHOT_PATH) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("BalanceHarness: could not open %s for writing (%s)" % [path, FileAccess.get_open_error()])
		return
	f.store_string(format_table(result))
	f.close()


static func _fmt_value(v: Variant) -> String:
	if typeof(v) == TYPE_FLOAT:
		return "%.3f" % v
	return str(v)
