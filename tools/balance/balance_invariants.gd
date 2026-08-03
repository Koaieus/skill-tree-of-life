class_name BalanceInvariants
extends RefCounted

## Ratio-invariant checker for the #268 balance harness. Reads
## `invariants.json` (every range ships `TBD` — filling one in is a #248
## pinning-session decision, never the drone's, D-13) and reports one of
## `OK` / `OUT (value vs range)` / `TBD` per invariant.
##
## AMENDMENT (2026-08-03): this is informative only, never a build gate. An
## `OUT` reading is a printed observation exactly like `TBD` — it must never
## fail `mise run balance` or the GUT test. Non-zero exit is reserved for the
## harness itself crashing.

const CONFIG_PATH := "res://tools/balance/invariants.json"


static func load_config() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("BalanceInvariants: missing config at %s" % CONFIG_PATH)
		return {"invariants": []}
	var text := FileAccess.get_file_as_string(CONFIG_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("BalanceInvariants: %s did not parse to a Dictionary" % CONFIG_PATH)
		return {"invariants": []}
	return parsed


## `scenarios` is the Array[Dictionary] from `BalanceScenarios.run_all` —
## each `{"name": ..., "readouts": {...}}`. Returns one row per configured
## invariant: `{"name", "status", "detail", "why"}`. Never raises/fails —
## every branch resolves to a status string.
static func check(scenarios: Array[Dictionary]) -> Array[Dictionary]:
	var by_name: Dictionary = {}
	for s in scenarios:
		by_name[s["name"]] = s["readouts"]

	var config := load_config()
	var results: Array[Dictionary] = []
	for inv in config.get("invariants", []):
		var scenario_name: String = inv.get("scenario", "")
		var readout_key: String = inv.get("readout", "")
		var readouts: Dictionary = by_name.get(scenario_name, {})
		var value: Variant = readouts.get(readout_key, null)
		var min_v: Variant = inv.get("min", "TBD")
		var max_v: Variant = inv.get("max", "TBD")

		var status: String
		var detail: String
		if value == null:
			status = "TBD"
			detail = "no value (scenario '%s' / readout '%s' not found)" % [scenario_name, readout_key]
		elif typeof(min_v) == TYPE_STRING or typeof(max_v) == TYPE_STRING:
			status = "TBD"
			detail = "%s (range not yet pinned)" % _fmt(value)
		elif typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
			status = "TBD"
			detail = "%s (non-numeric readout)" % str(value)
		else:
			var v := float(value)
			if v >= float(min_v) and v <= float(max_v):
				status = "OK"
				detail = "%s in [%s, %s]" % [_fmt(value), str(min_v), str(max_v)]
			else:
				status = "OUT"
				detail = "%s vs [%s, %s]" % [_fmt(value), str(min_v), str(max_v)]

		results.append({
			"name": inv.get("name", "?"),
			"status": status,
			"detail": detail,
			"why": inv.get("why", ""),
		})
	return results


static func _fmt(v: Variant) -> String:
	if typeof(v) == TYPE_FLOAT:
		return "%.3f" % v
	return str(v)
