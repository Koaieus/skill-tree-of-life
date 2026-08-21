extends GutTest

## The rule itself (#460), tested against a hand-built [VictoryContext] with no
## scene tree — [LastCampStandingCondition] is pure, and pinning it here keeps
## the "who won" question separate from the "when do we ask" question that
## `test_victory_system.gd` covers.

const _PLAYER := preload("res://entity/factions/player.tres")
const _NPC := preload("res://entity/factions/npc.tres")
const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _BLOCKER := preload("res://entity/factions/blocker.tres")

var _condition: LastCampStandingCondition


func before_each() -> void:
	_condition = LastCampStandingCondition.new()


## An entity is a bag of (faction, is_dead) as far as the condition cares.
func _ent(faction: Faction, dead: bool = false) -> Entity:
	var e := Entity.new()
	e.faction = faction
	e.is_dead = dead
	return autofree(e) as Entity


func _ctx(entities: Array, local: Faction = _PLAYER) -> VictoryContext:
	var ctx := VictoryContext.new()
	ctx.local_camp = local
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
	assert_eq(outcome.local_result, RunOutcome.LocalResult.WIN)


func test_a_camp_survives_on_any_living_entity_not_on_roster_seats() -> void:
	# Two NPC entities, one dead: the camp is still standing on the other.
	var ctx := _ctx([_ent(_PLAYER), _ent(_NPC, true), _ent(_NPC)])

	assert_null(_condition.evaluate(ctx))


func test_blockers_do_not_keep_a_run_alive() -> void:
	# Owner call: "Blocker NPCs do not count; they are inert scenery."
	var outcome := _condition.evaluate(
			_ctx([_ent(_PLAYER), _ent(_NPC, true), _ent(_BLOCKER), _ent(_BLOCKER)]))

	assert_not_null(outcome, "living blockers must not hold the run open")
	assert_eq(outcome.winning_camp.id, &"player")
	assert_eq(outcome.local_result, RunOutcome.LocalResult.WIN)


func test_blockers_alone_are_not_a_winning_camp_either() -> void:
	var outcome := _condition.evaluate(_ctx([_ent(_PLAYER, true), _ent(_BLOCKER)]))

	assert_not_null(outcome)
	assert_null(outcome.winning_camp, "a dormant core cannot win a run")
	assert_eq(outcome.local_result, RunOutcome.LocalResult.DRAW)


func test_mutual_wipe_is_a_draw() -> void:
	var outcome := _condition.evaluate(_ctx([_ent(_PLAYER, true), _ent(_NPC, true)]))

	assert_not_null(outcome, "a mutual wipe still ends the run")
	assert_null(outcome.winning_camp)
	assert_eq(outcome.local_result, RunOutcome.LocalResult.DRAW)


func test_single_player_death_degrades_to_a_loss() -> void:
	var outcome := _condition.evaluate(_ctx([_ent(_PLAYER, true), _ent(_NPC)]))

	assert_not_null(outcome)
	assert_eq(outcome.winning_camp.id, &"npc")
	assert_eq(outcome.local_result, RunOutcome.LocalResult.LOSS)


func test_single_player_clearing_the_board_is_a_win() -> void:
	var outcome := _condition.evaluate(
			_ctx([_ent(_PLAYER), _ent(_NPC, true), _ent(_CAMP_1, true)]))

	assert_not_null(outcome)
	assert_eq(outcome.winning_camp.id, &"player")
	assert_eq(outcome.local_result, RunOutcome.LocalResult.WIN)


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
	assert_eq(outcome.local_result, RunOutcome.LocalResult.LOSS)


func test_an_ai_only_run_reports_a_draw_from_nobodys_point_of_view() -> void:
	var outcome := _condition.evaluate(_ctx([_ent(_NPC), _ent(_CAMP_1, true)], null))

	assert_not_null(outcome)
	assert_eq(outcome.winning_camp.id, &"npc", "the run still names its winner")
	assert_eq(outcome.local_result, RunOutcome.LocalResult.DRAW,
			"with no local camp there is no local result")


func test_outcome_carries_the_turn_count() -> void:
	var ctx := _ctx([_ent(_PLAYER), _ent(_NPC, true)])
	ctx.turn_count = 17

	assert_eq(_condition.evaluate(ctx).turn_count, 17)


func test_run_config_defaults_every_mode_to_last_camp_standing() -> void:
	for mode in [RunConfig.Mode.SINGLE, RunConfig.Mode.COOP_HOTSEAT, RunConfig.Mode.VERSUS]:
		var cfg := RunConfig.new()
		cfg.mode = mode
		assert_true(cfg.resolved_victory_condition() is LastCampStandingCondition,
				"mode %s should default to last-camp-standing" % mode)


func test_run_config_honours_an_authored_condition() -> void:
	var cfg := RunConfig.new()
	var authored := VictoryCondition.new()
	cfg.victory_condition = authored

	assert_eq(cfg.resolved_victory_condition(), authored)
