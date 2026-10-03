extends GutTest

## [TurnLimitCondition] (#1257): once the limit is reached, the camp with the
## highest summed lifetime XP ([method GrowablePoolStat.total]) wins, ties broken
## by owned territory; an exact tie on both is a DRAW. Pure — every case is a
## hand-built [VictoryContext].

const _PLAYER := preload("res://entity/factions/player.tres")
const _NPC := preload("res://entity/factions/npc.tres")
const _BOARD := preload("res://entity/default_entity_board.tres")

const _LIMIT := 3


## Hands the condition a fixed node list — the territory walk reads nothing else.
class _StubGraph:
	extends Graph
	var nodes: Array[SkillNode] = []
	func get_skill_nodes() -> Array[SkillNode]:
		return nodes.duplicate()


## [param total] is the entity's lifetime XP, arranged as banked levels over an
## empty bar — the banking arithmetic itself is test_growable_pool_stat_def's.
func _ent(faction: Faction, level: int = 1, total: float = 0.0, dead: bool = false) -> Entity:
	var e := Entity.new()
	e.faction = faction
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	e.stat_board.level.base_value = level
	(e.stat_board.xp as GrowablePoolStat).banked = total
	e.stat_board.xp.current = 0.0
	e.is_dead = dead
	return autofree(e) as Entity


## A graph of one node per entry of [param owners], each owned by that entity.
func _graph(owners: Array) -> Graph:
	var g: _StubGraph = autofree(_StubGraph.new())
	for o in owners:
		var n: SkillNode = autofree(SkillNode.new())
		n.owned_by = o as Entity
		g.nodes.append(n)
	return g


func _ctx(entities: Array, rounds: int = _LIMIT, turns: int = 0, graph: Graph = null) -> VictoryContext:
	var ctx := VictoryContext.new()
	ctx.graph = graph
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


func test_the_higher_summed_total_xp_wins() -> void:
	# NPC has the best single entity, the player camp the higher sum.
	var ents := [_ent(_PLAYER, 3, 10.0), _ent(_PLAYER, 3, 10.0), _ent(_NPC, 5, 15.0)]
	var outcome := _condition().evaluate(_ctx(ents))
	assert_not_null(outcome)
	assert_eq(outcome.winning_camp.id, _PLAYER.id, "summed over the camp, not best entity")


## Level and bar don't add across members: three level-2s (Σlevel 6, total 15)
## lose to one level-4 (Σlevel 4, total 30) on lifetime XP.
func test_total_xp_beats_summed_level_across_members() -> void:
	var ents := [_ent(_PLAYER, 2, 5.0), _ent(_PLAYER, 2, 5.0), _ent(_PLAYER, 2, 5.0),
			_ent(_NPC, 4, 30.0)]
	var outcome := _condition().evaluate(_ctx(ents))
	assert_not_null(outcome)
	assert_eq(outcome.winning_camp.id, _NPC.id, "30 total XP beats 15, whatever the summed level")


func test_a_full_tie_is_a_draw() -> void:
	var ents := [_ent(_PLAYER, 2, 4.0), _ent(_NPC, 2, 4.0)]
	var outcome := _condition().evaluate(_ctx(ents))
	assert_not_null(outcome, "a tie still ends the run")
	assert_null(outcome.winning_camp, "an exact tie is a DRAW")


func test_excluded_contestants_never_score() -> void:
	var scenery := _ent(_NPC, 50, 50.0)
	scenery.add_to_group(&"scenery")
	var ents := [_ent(_PLAYER, 2, 5.0), _ent(_NPC, 1), scenery]
	var outcome := _condition().evaluate(_ctx(ents))
	assert_eq(outcome.winning_camp.id, _PLAYER.id, "scenery's XP never counts for its camp")


func test_the_dead_never_score() -> void:
	var ents := [_ent(_PLAYER, 2, 5.0), _ent(_NPC, 1), _ent(_NPC, 9, 50.0, true)]
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


func test_equal_total_xp_breaks_on_owned_territory() -> void:
	var p := _ent(_PLAYER, 2, 4.0)
	var n := _ent(_NPC, 2, 4.0)
	var outcome := _condition().evaluate(_ctx([p, n], _LIMIT, 0, _graph([n, p, n])))
	assert_not_null(outcome)
	assert_eq(outcome.winning_camp.id, _NPC.id, "two nodes beat one at equal total XP")


func test_a_tie_on_total_xp_and_territory_is_a_draw() -> void:
	var p := _ent(_PLAYER, 2, 4.0)
	var n := _ent(_NPC, 2, 4.0)
	var outcome := _condition().evaluate(_ctx([p, n], _LIMIT, 0, _graph([n, p, null])))
	assert_not_null(outcome)
	assert_null(outcome.winning_camp, "equal on both is a DRAW")


func test_territory_of_the_dead_and_of_non_contestants_never_counts() -> void:
	var p := _ent(_PLAYER, 2, 4.0)
	var n := _ent(_NPC, 2, 4.0)
	var corpse := _ent(_NPC, 0, 0.0, true)
	var scenery := _ent(_NPC, 0, 0.0)
	scenery.add_to_group(&"scenery")
	var g := _graph([p, corpse, corpse, scenery, scenery])
	var outcome := _condition().evaluate(_ctx([p, n, corpse, scenery], _LIMIT, 0, g))
	assert_eq(outcome.winning_camp.id, _PLAYER.id,
			"only living contestants' nodes count for their camp")


func test_describe_names_the_limit_and_its_unit() -> void:
	for limit in [_LIMIT, _LIMIT * 7]:
		var c := _condition()
		c.limit = limit
		var rounds := c.describe()
		assert_string_contains(rounds, str(limit))
		assert_string_contains(rounds, "round")
		c.unit = TurnLimitCondition.Unit.ENTITY_TURNS
		var turns := c.describe()
		assert_string_contains(turns, str(limit))
		assert_string_contains(turns, "entity turn")
		assert_false(turns.contains("round"), "an entity-turn limit never says rounds")
