extends GutTest

## [VictorySystem] (#460) — the *when* and the *once*, against real entities on
## the real death bus. What the rule decides is pinned separately in
## `test/unit/session/test_victory_condition.gd`.
##
## Note every entity here is built with `Entity.new()` and never through a
## scene: contest membership (#517) is a FILTER over the one
## [constant Entity.GROUP] walk, so a bare-constructed fixture must still be
## evaluated for victory.

const _PLAYER := preload("res://entity/factions/player.tres")
const _NPC := preload("res://entity/factions/npc.tres")
const _BLOCKER := preload("res://entity/factions/blocker.tres")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _victory: VictorySystem
var _outcomes: Array[RunOutcome] = []


func before_each() -> void:
	_outcomes = []
	_victory = VictorySystem.new()
	# #667: what `GameRoot` raises at the tail of its `_ready` once the world
	# exists. Every test below is about a world that already does — the guard
	# itself is pinned by the two `world_ready` cases at the bottom of the file.
	_victory.world_ready = true
	add_child_autofree(_victory)
	_victory.run_ended.connect(func(o: RunOutcome) -> void: _outcomes.append(o))


## A minimal live entity: in the tree (so it joins `Entity.GROUP`, which is
## where VictorySystem reads the roster from) with a board so `_ready` wiring
## has something to bind.
func _spawn(ent_name: String, faction: Faction, scenery: bool = false) -> Entity:
	var e := Entity.new()
	e.name = ent_name
	e.display_name = ent_name
	e.faction = faction
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	if scenery:
		# What `blocker_entity.tscn` authors in the inspector (#517) — contest
		# membership is a group the victory rule reads, not a faction flag.
		e.add_to_group(&"scenery")
	add_child_autofree(e)
	return e


## Mirrors GameRoot's synchronous turn-loop pull, which is what actually takes
## a dead NPC out of `Entity.GROUP` in a real level.
func _kill(e: Entity) -> void:
	e.die()
	e.remove_from_group(Entity.GROUP)


func test_a_run_with_two_camps_standing_does_not_end() -> void:
	_spawn("Player", _PLAYER)
	var npc_a := _spawn("NpcA", _NPC)
	_spawn("NpcB", _NPC)

	_kill(npc_a)
	await get_tree().process_frame

	assert_eq(_outcomes.size(), 0, "one camp still has a living entity")
	assert_null(_victory.outcome)


func test_killing_the_last_entity_of_a_camp_ends_the_run() -> void:
	_spawn("Player", _PLAYER)
	var npc := _spawn("Npc", _NPC)

	_kill(npc)
	await get_tree().process_frame

	assert_eq(_outcomes.size(), 1)
	assert_eq(_outcomes[0].winning_camp.id, &"player")
	assert_eq(_victory.outcome, _outcomes[0], "the outcome is latched on the system")


func test_scenery_left_on_the_board_does_not_keep_the_run_alive() -> void:
	_spawn("Player", _PLAYER)
	var npc := _spawn("Npc", _NPC)
	_spawn("BlockerA", _BLOCKER, true)
	_spawn("BlockerB", _BLOCKER, true)

	_kill(npc)
	await get_tree().process_frame

	assert_eq(_outcomes.size(), 1, "two living blockers must not hold the run open")
	assert_eq(_outcomes[0].winning_camp.id, &"player")


## The tutorial case, live on the real death bus (#517): one blocker IN the
## contest, its same-faction siblings out. The run stays open while it lives and
## ends when it dies — membership decided per entity, not per camp.
func test_a_blocker_in_the_contest_keeps_the_run_open_until_it_dies() -> void:
	_spawn("Player", _PLAYER)
	var npc := _spawn("Npc", _NPC)
	var contender := _spawn("Contender", _BLOCKER)
	_spawn("Scenery", _BLOCKER, true)

	_kill(npc)
	await get_tree().process_frame
	assert_eq(_outcomes.size(), 0, "a blocker outside `scenery` is a real camp")

	_kill(contender)
	await get_tree().process_frame

	assert_eq(_outcomes.size(), 1, "its sceneried sibling must not hold the run open")
	assert_eq(_outcomes[0].winning_camp.id, &"player")


## The reason evaluation is coalesced: deaths arrive one signal at a time, so an
## inline evaluation would see the first of a simultaneous pair leave one camp
## standing and declare a WIN before the second death ever fired.
func test_a_mutual_wipe_in_one_batch_is_a_draw_not_a_win() -> void:
	var player := _spawn("Player", _PLAYER)
	var npc := _spawn("Npc", _NPC)

	_kill(npc)
	_kill(player)
	await get_tree().process_frame

	assert_eq(_outcomes.size(), 1, "one terminal announcement, not two")
	assert_null(_outcomes[0].winning_camp)


func test_the_outcome_is_announced_exactly_once() -> void:
	_spawn("Player", _PLAYER)
	var npc_a := _spawn("NpcA", _NPC)
	var npc_b := _spawn("NpcB", _NPC)

	_kill(npc_a)
	_kill(npc_b)
	await get_tree().process_frame
	var first: RunOutcome = _outcomes[0]

	# Every later death still fires the death signal; none may re-announce.
	_kill(_spawn("NpcC", _NPC))
	await get_tree().process_frame

	assert_eq(_outcomes.size(), 1, "the latch must survive further deaths")
	assert_eq(_victory.outcome, first)


func test_the_player_dying_leaves_the_surviving_camp_the_winner() -> void:
	var player := _spawn("Player", _PLAYER)
	_spawn("Npc", _NPC)

	_kill(player)
	await get_tree().process_frame

	assert_eq(_outcomes.size(), 1)
	assert_eq(_outcomes[0].winning_camp.id, &"npc")


func test_the_outcome_reports_the_turn_count() -> void:
	var turns := TurnManager.new()
	add_child_autofree(turns)
	turns.turns_taken = 9
	_victory.turn_manager = turns
	_spawn("Player", _PLAYER)
	var npc := _spawn("Npc", _NPC)

	_kill(npc)
	await get_tree().process_frame

	assert_eq(_outcomes[0].turn_count, 9)


func test_the_bus_carries_the_same_outcome() -> void:
	var seen: Array[RunOutcome] = []
	var handler := func(o: RunOutcome) -> void: seen.append(o)
	Events.run_ended.connect(handler)

	_spawn("Player", _PLAYER)
	_kill(_spawn("Npc", _NPC))
	await get_tree().process_frame
	Events.run_ended.disconnect(handler)

	assert_eq(seen.size(), 1)
	assert_eq(seen[0], _outcomes[0])


# ── #667: the readiness guard ────────────────────────────────────────────────
## Asserted DIRECTLY, with no network anywhere near it: the ejection this guard
## prevents does not need a wire to reproduce. A world mid-generation normally
## has one camp spawned and the rest not yet, which is precisely the shape
## `LastCampStandingCondition` calls a WIN — and [member VictorySystem.outcome]
## has no reset within a scene lifetime, so latching it once is terminal.
func test_a_death_before_the_world_is_ready_does_not_latch_an_outcome() -> void:
	_victory.world_ready = false
	_spawn("Player", _PLAYER)
	var npc := _spawn("Npc", _NPC)

	_kill(npc)
	await get_tree().process_frame

	assert_eq(_outcomes.size(), 0, "a partial roster is not a verdict")
	assert_null(_victory.outcome, "the latch must not fire — nothing can un-fire it")


## The single-entity world the guard exists for, and the proof it is a DEFERRAL
## and not a mute: the same roster, judged again once the world is declared
## ready, still ends the run.
func test_the_lone_camp_of_a_half_built_world_is_ignored_then_judged() -> void:
	_victory.world_ready = false
	_spawn("Player", _PLAYER)

	_victory.evaluate_now()
	assert_null(_victory.outcome, "one camp standing mid-generation is the normal state")

	_victory.world_ready = true
	_victory.evaluate_now()

	assert_eq(_outcomes.size(), 1, "the same world is judged once it is ready")
	assert_eq(_outcomes[0].winning_camp.id, &"player")
