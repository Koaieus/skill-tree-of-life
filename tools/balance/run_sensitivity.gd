extends SceneTree

## 1-D sensitivity slice (#268 scope D): holds one named scenario's level
## fixed, varies one attacker stat over a range, and prints the
## combat-facing readouts at each step. Never a full sweep — one slice
## through a pinned point. Run via:
##
##     mise run balance:sensitivity -- <scenario> <stat> <from> <to> <step>
##     # e.g. mise run balance:sensitivity -- mirror_L20 dexterity 5 40 5
##
## `<scenario>` only supplies the level band (both sides plain BalancedCore at
## that level) — the scenario's own attacker/defender pairing (e.g. the
## zero-investment attacker in `matched_L100_zero_invest`) is not replayed
## here; this mode exists to isolate one stat, not to reproduce every fixture
## verbatim.
##
## Dynamic `load()` throughout, never a top-level `preload`/global-class
## reference — see `run_balance.gd`'s docstring for why: `--script` mode
## compiles everything this file statically references BEFORE the project's
## autoloads exist, and the fixture chain (`Entity` et al.) needs them.

## Scenario name -> level. Mirrors `BalanceScenarios.NAMES`; kept as a
## separate small map here (rather than exposing level as a first-class field
## on the scenario dict) since sensitivity mode only ever needs the level.
const _LEVELS := {
	"mirror_L5": 5,
	"mirror_L20": 20,
	"mirror_L50": 50,
	"matched_L100_zero_invest": 100,
	"asymmetric_snipe_L20_vs_L80": 20,
	"core_adjacent_aura_L50": 50,
}


func _initialize() -> void:
	call_deferred("_start")


func _start() -> void:
	await process_frame
	await process_frame
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 5:
		printerr("usage: mise run balance:sensitivity -- <scenario> <stat> <from> <to> <step>")
		printerr("known scenarios: %s" % ", ".join(_LEVELS.keys()))
		quit(1)
		return

	var scenario_name: String = args[0]
	var stat_name := StringName(args[1])
	var from_v: float = float(args[2])
	var to_v: float = float(args[3])
	var step_v: float = float(args[4])

	if not _LEVELS.has(scenario_name):
		printerr("unknown scenario '%s'. known: %s" % [scenario_name, ", ".join(_LEVELS.keys())])
		quit(1)
		return
	if step_v <= 0.0:
		printerr("step must be > 0")
		quit(1)
		return

	var fixture_script = load("res://tools/balance/balance_fixture.gd")
	var scenarios_script = load("res://tools/balance/balance_scenarios.gd")
	var balanced_core = load("res://entity/core/balanced_core.tres")

	var level: int = _LEVELS[scenario_name]
	print("# Sensitivity slice: %s (level %d), stat=%s, %.1f..%.1f step %.1f" \
		% [scenario_name, level, stat_name, from_v, to_v, step_v])
	print("")
	print("| %s | ranged_raw | melee_raw | mitigated_ranged | mitigated_melee | hits_to_drop_node |" % stat_name)
	print("|---|---|---|---|---|---|")

	var v := from_v
	while v <= to_v + 0.0001:
		var attacker = await fixture_script.build(root, level, balanced_core)
		var defender = await fixture_script.build(root, level, balanced_core)

		var stat = attacker.entity.stat_board.get_stat(stat_name)
		if stat == null:
			printerr("unknown stat '%s' on the entity board" % stat_name)
			scenarios_script.free_fixture(attacker)
			scenarios_script.free_fixture(defender)
			quit(1)
			return
		stat.base_value = v

		var readouts: Dictionary = scenarios_script.combat_readouts(attacker, defender)
		print("| %.2f | %.3f | %.3f | %.3f | %.3f | %s |" % [
			v,
			readouts["ranged_damage_raw"],
			readouts["melee_damage_raw"],
			readouts["mitigated_ranged_damage"],
			readouts["mitigated_melee_damage"],
			str(readouts["hits_to_drop_node"]),
		])

		scenarios_script.free_fixture(attacker)
		scenarios_script.free_fixture(defender)
		v += step_v

	quit(0)
