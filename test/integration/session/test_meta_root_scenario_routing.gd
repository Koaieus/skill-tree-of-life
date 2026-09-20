extends GutTest

## #641 acceptance 4 — moving `RunConfig.level_scene` onto [Scenario] only
## discharges #584 D5 if the READER moved too; "moving the field without
## moving its reader relocates the smell instead of discharging it," per the
## issue itself. `MetaRoot._destination_for` is `static` for exactly the
## reason `_stamp_local_peer` already is (`test_meta_routing_parity.gd`) — so
## it is callable here directly, without driving the whole frontmatter tree
## `test_meta_routing_parity.gd` needs for the rest of `meta_root.gd`'s
## routing.

const _META_SCRIPT := preload("res://scenes/meta/meta_root.gd")
## Deliberately NOT `res://scenes/level.tscn` — [constant MetaRoot.FIRST_LEVEL_SANDBOX]
## itself, so a scenario naming it would pass this test even if the fallback
## fired instead of the scenario's own field. `procgen_play_sandbox.tscn` is a
## real level scene that is provably NOT that constant.
const _OTHER_LEVEL_SCENE := preload("res://scenes/procgen_play_sandbox.tscn")


func test_no_scenario_falls_back_to_the_first_level_sandbox() -> void:
	var cfg := RunConfig.new()
	assert_eq(_META_SCRIPT._destination_for(cfg), _META_SCRIPT.FIRST_LEVEL_SANDBOX)


func test_a_scenario_naming_a_level_scene_wins_over_the_fallback() -> void:
	assert_ne(_OTHER_LEVEL_SCENE, _META_SCRIPT.FIRST_LEVEL_SANDBOX,
			"precondition: the scenario below must name a DIFFERENT scene than the fallback")
	var scenario := Scenario.new()
	scenario.level_scene = _OTHER_LEVEL_SCENE
	var cfg := RunConfig.new()
	cfg.scenario = scenario
	assert_eq(_META_SCRIPT._destination_for(cfg), _OTHER_LEVEL_SCENE)


func test_a_scenario_with_no_level_scene_falls_back_too() -> void:
	# `session/scenarios/procgen_play.tres` is exactly this shape today — a
	# Scenario meant only for its own RunBootstrap sandbox, which cannot name
	# itself as `level_scene` (a resource-loader cycle; see the docstring on
	# `Scenario.level_scene`).
	var cfg := RunConfig.new()
	var scenario := Scenario.new()
	scenario.preset = GraphProcgenConfig.new()
	cfg.scenario = scenario
	assert_eq(_META_SCRIPT._destination_for(cfg), _META_SCRIPT.FIRST_LEVEL_SANDBOX)
