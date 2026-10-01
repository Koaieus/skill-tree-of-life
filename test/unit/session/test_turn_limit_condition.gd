extends GutTest

## [TurnLimitCondition] (#1257): once the limit is reached, the camp with the
## highest summed level wins, ties broken by summed `xp.current`; an exact tie
## is a DRAW. Pure — every case is a hand-built [VictoryContext].

const _PLAYER := preload("res://entity/factions/player.tres")
const _NPC := preload("res://entity/factions/npc.tres")
const _BOARD := preload("res://entity/default_entity_board.tres")

const _LIMIT := 3


func _ent(faction: Faction, level: int = 1, xp: float = 0.0, dead: bool = false) -> Entity:
	var e := Entity.new()
	e.faction = faction
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	e.stat_board.level.base_value = level
	e.stat_board.xp.current = xp
	e.is_dead = dead
	return autofree(e) as Entity


func _ctx(entities: Array, rounds: int = _LIMIT, turns: int = 0) -> VictoryContext:
	var ctx := VictoryContext.new()
	for e in entities:
		ctx.entities.append(e as Entity)
	ctx.rounds_completed = rounds
	ctx.turn_count = turns
	return ctx


func _condition(unit: TurnLimitCondition.Unit = TurnLimitCondition.Unit.ROUNDS) -> TurnLimitCondition:
	var c := TurnLimitCondition.new()
	c.limit = _LIMIT
	c.unit = unit
	return c


func test_rounds_returns_null_before_the_limit_and_fires_on_it() -> void:
	var c := _condition()
	var ents := [_ent(_PLAYER, 2), _ent(_NPC, 1)]
	assert_null(c.evaluate(_ctx(ents, _LIMIT - 1)), "one round short: the run continues")
	var outcome := c.evaluate(_ctx(ents, _LIMIT))
	assert_not_null(outcome, "the limit is reached: the run ends")
	assert_null(c.evaluate(_ctx(ents, 0, _LIMIT * 10)),
			"ROUNDS never reads the entity-turn count")


func test_the_higher_summed_level_wins() -> void:
	# NPC has the best single entity, the player camp the higher sum.
	var ents := [_ent(_PLAYER, 3), _ent(_PLAYER, 3), _ent(_NPC, 5)]
	var outcome := _condition().evaluate(_ctx(ents))
	assert_not_null(outcome)
	assert_eq(outcome.winning_camp.id, _PLAYER.id, "summed over the camp, not best entity")


func test_equal_levels_break_on_summed_xp() -> void:
	var ents := [_ent(_PLAYER, 2, 5.0), _ent(_NPC, 2, 3.0), _ent(_NPC, 0, 3.0)]
	var outcome := _condition().evaluate(_ctx(ents))
	assert_not_null(outcome)
	assert_eq(outcome.winning_camp.id, _NPC.id, "6 xp beats 5 xp at equal level")


func test_a_full_tie_is_a_draw() -> void:
	var ents := [_ent(_PLAYER, 2, 4.0), _ent(_NPC, 2, 4.0)]
	var outcome := _condition().evaluate(_ctx(ents))
	assert_not_null(outcome, "a tie still ends the run")
	assert_null(outcome.winning_camp, "an exact tie is a DRAW")


func test_excluded_contestants_never_score() -> void:
	var scenery := _ent(_NPC, 50, 50.0)
	scenery.add_to_group(&"scenery")
	var ents := [_ent(_PLAYER, 2), _ent(_NPC, 1), scenery]
	var outcome := _condition().evaluate(_ctx(ents))
	assert_eq(outcome.winning_camp.id, _PLAYER.id, "scenery's levels never count for its camp")


func test_the_dead_never_score() -> void:
	var ents := [_ent(_PLAYER, 2), _ent(_NPC, 1), _ent(_NPC, 9, 0.0, true)]
	var outcome := _condition().evaluate(_ctx(ents))
	assert_eq(outcome.winning_camp.id, _PLAYER.id, "only living members are summed")


func test_entity_turns_fires_on_turn_count() -> void:
	var c := _condition(TurnLimitCondition.Unit.ENTITY_TURNS)
	var ents := [_ent(_PLAYER, 2), _ent(_NPC, 1)]
	assert_null(c.evaluate(_ctx(ents, _LIMIT * 10, _LIMIT - 1)),
			"ENTITY_TURNS never reads the round count")
	var outcome := c.evaluate(_ctx(ents, 0, _LIMIT))
	assert_not_null(outcome)
	assert_eq(outcome.turn_count, _LIMIT)
