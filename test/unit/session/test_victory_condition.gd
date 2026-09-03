extends GutTest

## The rule itself (#460/#517), tested against a hand-built [VictoryContext]
## with no scene tree — [LastCampStandingCondition] is pure, and pinning it here
## keeps the "who won" question separate from the "when do we ask" question that
## `test_victory_system.gd` covers.
##
## Contest membership is a [ContestantRule] the condition owns (#517), so the
## inert-scenery fixtures below join the `scenery` GROUP rather than wearing a
## faction that opts the whole camp out.

const _PLAYER := preload("res://entity/factions/player.tres")
const _NPC := preload("res://entity/factions/npc.tres")
const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _BLOCKER := preload("res://entity/factions/blocker.tres")
const _BLOCKER_SCENE := preload("res://entity/blocker/blocker_entity.tscn")
const _SCENERY := &"scenery"

var _condition: LastCampStandingCondition


func before_each() -> void:
	_condition = LastCampStandingCondition.new()


## An entity is a bag of (faction, is_dead, groups) as far as the condition
## cares.
func _ent(faction: Faction, dead: bool = false, scenery: bool = false) -> Entity:
	var e := Entity.new()
	e.faction = faction
	e.is_dead = dead
	if scenery:
		e.add_to_group(_SCENERY)
	return autofree(e) as Entity


## Inert scenery: a blocker-faction entity that has authored itself OUT of the
## contest, which is what `blocker_entity.tscn` ships as.
func _scenery(dead: bool = false) -> Entity:
	return _ent(_BLOCKER, dead, true)


func _ctx(entities: Array) -> VictoryContext:
	var ctx := VictoryContext.new()
	for e in entities:
		ctx.entities.append(e as Entity)
	return ctx


func test_two_living_camps_means_the_run_continues() -> void:
	assert_null(_condition.evaluate(_ctx([_ent(_PLAYER), _ent(_NPC)])),
			"a run with two camps standing must not end")


func test_killing_the_last_entity_of_one_camp_wins_it_for_the_other() -> void:
	var outcome := _condition.evaluate(_ctx([_ent(_PLAYER), _ent(_NPC, true)]))

	assert_not_null(outcome, "one camp left should end the run")
	assert_eq(outcome.winning_camp.id, &"player")


func test_a_camp_survives_on_any_living_entity_not_on_roster_seats() -> void:
	# Two NPC entities, one dead: the camp is still standing on the other.
	var ctx := _ctx([_ent(_PLAYER), _ent(_NPC, true), _ent(_NPC)])

	assert_null(_condition.evaluate(ctx))


func test_scenery_does_not_keep_a_run_alive() -> void:
	# Owner call: "Blocker NPCs do not count; they are inert scenery."
	var outcome := _condition.evaluate(
			_ctx([_ent(_PLAYER), _ent(_NPC, true), _scenery(), _scenery()]))

	assert_not_null(outcome, "living scenery must not hold the run open")
	assert_eq(outcome.winning_camp.id, &"player")


func test_scenery_alone_is_not_a_winning_camp_either() -> void:
	var outcome := _condition.evaluate(_ctx([_ent(_PLAYER, true), _scenery()]))

	assert_not_null(outcome)
	assert_null(outcome.winning_camp, "a dormant core cannot win a run")


## The point of #517: inertness is per ENTITY, not per camp. Two entities on
## `blocker.tres`, one in `scenery` and one not — the second is a real camp.
func test_two_entities_of_one_faction_can_differ_on_contest_membership() -> void:
	var contender := _ent(_BLOCKER)

	assert_null(_condition.evaluate(_ctx([_ent(_PLAYER), contender, _scenery()])),
			"a blocker OUT of the scenery group is a camp and holds the run open")

	contender.is_dead = true
	var outcome := _condition.evaluate(_ctx([_ent(_PLAYER), contender, _scenery()]))
	assert_not_null(outcome, "its sceneried sibling must not keep the run going")
	assert_eq(outcome.winning_camp.id, &"player")


## Pull semantics: membership is re-read on every evaluation, never cached at
## spawn or stamped at run start. The same entity object changes answer when its
## group changes, with no re-build of anything.
func test_membership_is_re_read_at_evaluation_time_not_cached() -> void:
	var blocker := _ent(_BLOCKER, false, true)
	var ctx := _ctx([_ent(_PLAYER), blocker])

	assert_not_null(_condition.evaluate(ctx), "sceneried: the player stands alone")

	blocker.remove_from_group(_SCENERY)
	assert_null(_condition.evaluate(ctx), "un-sceneried live: back in the contest")

	blocker.is_dead = true
	assert_not_null(_condition.evaluate(ctx), "in the contest, but dead")


func test_mutual_wipe_is_a_draw() -> void:
	var outcome := _condition.evaluate(_ctx([_ent(_PLAYER, true), _ent(_NPC, true)]))

	assert_not_null(outcome, "a mutual wipe still ends the run")
	assert_null(outcome.winning_camp)


func test_the_player_dying_leaves_the_surviving_camp_the_winner() -> void:
	var outcome := _condition.evaluate(_ctx([_ent(_PLAYER, true), _ent(_NPC)]))

	assert_not_null(outcome)
	assert_eq(outcome.winning_camp.id, &"npc")


func test_clearing_the_board_leaves_the_player_the_winner() -> void:
	var outcome := _condition.evaluate(
			_ctx([_ent(_PLAYER), _ent(_NPC, true), _ent(_CAMP_1, true)]))

	assert_not_null(outcome)
	assert_eq(outcome.winning_camp.id, &"player")


func test_three_camps_need_two_wipes_to_end() -> void:
	var ctx := _ctx([_ent(_PLAYER), _ent(_NPC), _ent(_CAMP_1)])
	assert_null(_condition.evaluate(ctx), "three camps standing")

	ctx.entities[1].is_dead = true
	assert_null(_condition.evaluate(ctx), "two camps standing")

	ctx.entities[2].is_dead = true
	assert_not_null(_condition.evaluate(ctx), "one camp standing")


func test_camps_are_compared_by_id_not_by_resource_reference() -> void:
	# Faction identity is by `id` (see its class doc) — a duplicated .tres is
	# the same camp, and must not read as a second one holding the run open.
	var copy := _NPC.duplicate(true) as Faction

	assert_null(_condition.evaluate(_ctx([_ent(_PLAYER), _ent(_NPC)])))
	var outcome := _condition.evaluate(_ctx([_ent(_NPC), _ent(copy), _ent(_PLAYER, true)]))

	assert_not_null(outcome, "two copies of one faction are one camp, so it stands alone")
	assert_eq(outcome.winning_camp.id, &"npc")


func test_outcome_carries_the_turn_count() -> void:
	var ctx := _ctx([_ent(_PLAYER), _ent(_NPC, true)])
	ctx.turn_count = 17

	assert_eq(_condition.evaluate(ctx).turn_count, 17)


func test_the_outcome_names_a_winner_and_no_point_of_view() -> void:
	# #517: LOSS stopped being a world fact. A run has one winner and as many
	# points of view as there are machines watching.
	var outcome := _condition.evaluate(_ctx([_ent(_PLAYER), _ent(_NPC, true)]))

	var props: Array = outcome.get_property_list().map(
			func(p: Dictionary) -> String: return p.get("name", ""))
	assert_false(props.has("local_result"),
			"RunOutcome must carry no point of view")
	assert_eq(outcome.winning_camp.id, &"player", "it still names its winner")


## A rule is optional: a condition built with none counts everyone rather than
## crashing or silently producing a run that can never end.
func test_a_null_contestant_rule_counts_everyone() -> void:
	_condition.contestants = null
	var ctx := _ctx([_ent(_PLAYER), _scenery()])

	assert_null(_condition.evaluate(ctx),
			"with no rule even scenery is a camp, and two camps stand")


func test_the_default_rule_excludes_the_scenery_group() -> void:
	assert_true(_condition.contestants is ExcludeGroupRule,
			"the shipped default is the scenery exclusion")
	assert_false(_condition.contestants.includes(_scenery()))
	assert_true(_condition.contestants.includes(_ent(_BLOCKER)))


## The literal `scenery` lives in two places with no compile-time link — the
## export default on [ExcludeGroupRule] and the `groups=` entry in
## `blocker_entity.tscn`. Pin the SHIPPED scene against the DEFAULT rule, with
## no per-test wiring, so a typo on either side fails here.
func test_the_shipped_blocker_scene_is_excluded_by_the_default_rule() -> void:
	var blocker: Entity = _BLOCKER_SCENE.instantiate()
	autofree(blocker)

	assert_true(blocker.is_in_group(_SCENERY),
			"blocker_entity.tscn must author itself out of the contest")
	assert_false(_condition.contestants.includes(blocker),
			"the default rule must exclude the shipped blocker")


func test_run_config_defaults_every_mode_to_last_camp_standing() -> void:
	for mode in [RunConfig.Mode.SINGLE, RunConfig.Mode.COOP_HOTSEAT, RunConfig.Mode.VERSUS]:
		var cfg := RunConfig.new()
		cfg.mode = mode
		assert_true(cfg.resolved_victory_condition() is LastCampStandingCondition,
				"mode %s should default to last-camp-standing" % mode)


## #638 acceptance 1: the condition is read off the [Scenario], not off the run.
## #742: resolution now goes through [method ScenarioOverride.merge_onto],
## which duplicates the [Scenario] unconditionally (same contract
## [method RunConfig.resolved_preset] already had) — so the resolved condition
## is never `==` the authored instance even with no overrides. Compared by
## script/type, the same way [method test_a_scenario_authoring_no_condition_falls_back_without_consulting_mode]
## already does for its own type-not-identity check.
func test_run_config_honours_the_scenarios_condition() -> void:
	var cfg := RunConfig.new()
	var authored := VictoryCondition.new()
	cfg.scenario = Scenario.new()
	cfg.scenario.victory_condition = authored

	assert_eq(cfg.resolved_victory_condition().get_script(), authored.get_script())


## #742: the whole point of rooting [ScenarioOverride] at [Scenario] instead of
## adding a second override list — a lobby's `target: "victory_condition"` pick
## must actually change what [method RunConfig.resolved_victory_condition]
## returns, not just what [method ScenarioOverride.merge_onto] returns in
## isolation (that half is already covered by
## `test_scenario_override_merge.gd`). This is the one seam real generation
## reads, so a merge skipped here would make the lobby control a no-op.
func test_a_victory_condition_override_changes_what_run_config_resolves() -> void:
	var cfg := RunConfig.new()
	cfg.scenario = Scenario.new()
	cfg.scenario.victory_condition = VictoryCondition.new()
	assert_false(cfg.resolved_victory_condition() is LastCampStandingCondition,
			"premise: the authored condition is the plain base type, not LastCampStanding")

	var override := ScenarioOverride.new()
	override.target = "victory_condition"
	override.value = "res://session/victory/last_camp_standing.tres"
	cfg.overrides = [override]

	var resolved := cfg.resolved_victory_condition()
	assert_true(resolved is LastCampStandingCondition,
			"the override must be reflected in what RunConfig resolves, overriding the authored condition")
	assert_true(cfg.scenario.victory_condition is VictoryCondition
			and not (cfg.scenario.victory_condition is LastCampStandingCondition),
			"the authored (pre-merge) Scenario must never be mutated")


## #638 acceptance 2, with the teeth the spec asks for: the fallback is the
## SCENARIO's own default and takes no mode. Every [enum RunConfig.Mode] is run
## against the SAME condition-less [Scenario] and every one must land on the
## same type — a reintroduced `mode -> condition` switch that answered
## differently for any mode fails here rather than passing silently the way the
## deleted single-arm `default_condition_for` did.
func test_a_scenario_authoring_no_condition_falls_back_without_consulting_mode() -> void:
	var scenario := Scenario.new()
	var scripts: Array = []
	for mode in [RunConfig.Mode.SINGLE, RunConfig.Mode.COOP_HOTSEAT, RunConfig.Mode.VERSUS]:
		var cfg := RunConfig.new()
		cfg.mode = mode
		cfg.scenario = scenario
		var resolved := cfg.resolved_victory_condition()
		assert_true(resolved is LastCampStandingCondition,
				"mode %s must fall back to last-camp-standing" % mode)
		scripts.append(resolved.get_script())
	assert_eq(scripts[0], scripts[1], "the fallback must not vary by mode")
	assert_eq(scripts[1], scripts[2], "the fallback must not vary by mode")
	assert_eq(scenario.resolved_victory_condition().get_script(), scripts[0],
			"and it must be the SCENARIO's answer, reachable with no RunConfig at all")


## #638 acceptance 3: `default_condition_for` is DELETED, not merely uncalled.
func test_run_config_no_longer_exposes_a_mode_keyed_condition_default() -> void:
	var src: GDScript = load("res://session/run_config.gd")
	assert_false(src.source_code.contains("default_condition_for"),
			"#638 acceptance 3: deleted, not left with no callers — "
			+ "a mode must never decide content (#615 D6)")


## #638 acceptance 5: a route whose [LobbyPolicy] does not unlock the slot
## offers no victory ladder, and the Scenario's condition is used unchanged.
func test_a_policy_that_does_not_unlock_the_slot_offers_no_victory_ladder() -> void:
	var policy := LobbyPolicy.new()
	assert_null(policy.victory_options,
			"no shipped route unlocks the victory slot yet (#638)")
	assert_false(policy.offers_run_section(),
			"an unauthored victory ladder must not conjure a run section")
