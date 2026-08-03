extends GutTest

## #268 — the balance harness executes end to end and writes its snapshot.
##
## AMENDMENT (2026-08-03): the harness is informative, never binding. This
## test asserts only that the full table runs without error and the snapshot
## is written — it must NOT fail on an `OUT` invariant reading. `OUT` is a
## printed observation, exactly like `TBD`.
##
## Unlike `run_balance.gd`, this file loads normally through GUT's own script
## loader (well after the tree + autoloads are up, like every other test
## here), so it uses the ordinary `preload`/global-class-name pattern rather
## than the dynamic-`load()` workaround `run_balance.gd` needs for `--script`
## mode (see that file's docstring).


func test_full_table_runs_and_writes_snapshot() -> void:
	var result: Dictionary = await BalanceHarness.run(self)

	assert_true(result.has("scenarios"), "result should carry a scenarios list")
	var scenarios: Array = result["scenarios"]
	assert_eq(scenarios.size(), BalanceScenarios.NAMES.size(),
		"every named scenario should have run")
	for s in scenarios:
		assert_true(s.has("readouts"), "%s should carry readouts" % s.get("name", "?"))
		assert_false((s["readouts"] as Dictionary).is_empty(),
			"%s should compute at least one readout" % s.get("name", "?"))

	assert_true(result.has("invariants"), "result should carry an invariants report")
	var invariants: Array = result["invariants"]
	assert_eq(invariants.size(), 6, "all 6 required invariants should be checked")
	for inv in invariants:
		# The amendment's hard constraint: OUT must never surface as a
		# failure here — only TBD/OK/OUT are legal statuses, and every range
		# ships TBD today, so a status of anything else (or a crash) is the
		# real regression to catch.
		assert_true(inv["status"] in ["OK", "OUT", "TBD"],
			"invariant %s has an unrecognized status %s" % [inv["name"], inv["status"]])

	BalanceHarness.write_snapshot(result)
	assert_true(FileAccess.file_exists(BalanceHarness.SNAPSHOT_PATH),
		"snapshot file should exist after write_snapshot")


func test_sensitivity_combat_readouts_react_to_the_varied_stat() -> void:
	var attacker := await BalanceFixture.build(self, 20, preload("res://entity/core/balanced_core.tres"))
	var defender := await BalanceFixture.build(self, 20, preload("res://entity/core/balanced_core.tres"))

	var before := BalanceScenarios.combat_readouts(attacker, defender)
	attacker.entity.stat_board.dexterity.base_value += 50.0
	var after := BalanceScenarios.combat_readouts(attacker, defender)

	assert_gt(after["ranged_damage_raw"], before["ranged_damage_raw"],
		"raising DEX should raise the attacker's ranged_damage reading")

	BalanceScenarios.free_fixture(attacker)
	BalanceScenarios.free_fixture(defender)
