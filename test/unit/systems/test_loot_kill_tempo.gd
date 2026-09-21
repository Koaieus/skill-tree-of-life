extends GutTest

## #888: tempo award. A HOSTILE killing blow spends 1 `tempo` to refund 1
## `action_points`, gated exactly like the XP reward (`_award_kill_xp`) plus
## the pool's own cap, which IS the once-per-turn latch — no separate bool, no
## per-attack ledger. Uses `Entity.die()` directly (not the health-overflow
## path `test_loot_system.gd` exercises for XP) since tempo cares only about
## the `Events.entity_dying` phase LootSystem reacts to, never territory.
##
## Cap is always set ON THE TEST BOARD, never read from the shipped
## `default_entity_board.tres` default (`owner_tunes_agents_test`) — the owner
## may tune or even zero it.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

var _graph: Graph
var _loot: LootSystem
var _tm: TurnManager
var _killer: Entity


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_tm = TurnManager.new()
	add_child_autofree(_tm)

	_loot = LootSystem.new()
	_loot.turn_manager = _tm
	add_child_autofree(_loot)

	_killer = autofree(Entity.new())
	_killer.display_name = "Killer"
	_killer.faction = _PLAYER_FACTION  # hostile to the default npc-faction victim
	_killer.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_killer)
	await get_tree().process_frame  # Entity._ready: board duplication + intrinsics

	_killer.stat_board.tempo.base_value = 1.0  # cap set on the test board, never the shipped default


func _spawn_victim(faction: Faction = _NPC_FACTION) -> Entity:
	var victim: Entity = autofree(Entity.new())
	victim.display_name = "Victim"
	victim.faction = faction
	victim.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(victim)
	await get_tree().process_frame
	return victim


func _kill(victim: Entity) -> void:
	# Attribution only — kills within ONE turn are the subject, so adopt.
	_tm.adopt_turn(_killer, _tm.turns_taken)
	victim.die()


func test_kill_refunds_ap_and_spends_tempo() -> void:
	_killer.stat_board.action_points.set_current(1.0)
	var victim := await _spawn_victim()
	_kill(victim)
	assert_eq(_killer.stat_board.action_points.current, 2.0, "AP 1/2 -> 2/2 on a killing blow")
	assert_eq(_killer.stat_board.tempo.current, 0.0, "tempo spent: 0/1")


func test_second_kill_same_turn_pays_nothing_more() -> void:
	_killer.stat_board.action_points.set_current(0.0)
	var v1 := await _spawn_victim()
	var v2 := await _spawn_victim()
	_kill(v1)
	var ap_after_first := _killer.stat_board.action_points.current
	var tempo_after_first := _killer.stat_board.tempo.current
	_kill(v2)
	assert_eq(_killer.stat_board.action_points.current, ap_after_first,
			"tempo is depleted -> no second refund this turn")
	assert_eq(_killer.stat_board.tempo.current, tempo_after_first, "tempo stays at 0")


func test_turn_start_upkeep_refills_tempo() -> void:
	var victim := await _spawn_victim()
	_kill(victim)
	assert_eq(_killer.stat_board.tempo.current, 0.0, "precondition: tempo spent")
	_killer.stat_board.apply_per_turn_upkeep()
	assert_eq(_killer.stat_board.tempo.current, 1.0, "tempo REFILLs to cap at turn start")


func test_ally_kill_pays_no_tempo() -> void:
	var victim := await _spawn_victim(_PLAYER_FACTION)  # same faction as killer -> ALLIED
	var ap_before := _killer.stat_board.action_points.current
	_kill(victim)
	assert_eq(_killer.stat_board.action_points.current, ap_before, "an ally kill refunds nothing")
	assert_eq(_killer.stat_board.tempo.current, 1.0, "tempo untouched by an ally kill")


func test_self_death_pays_no_tempo() -> void:
	var victim := await _spawn_victim()
	_tm.adopt_turn(null, _tm.turns_taken)  # no killer attribution
	var ap_before := _killer.stat_board.action_points.current
	victim.die()
	assert_eq(_killer.stat_board.action_points.current, ap_before, "no killer -> no refund")
	assert_eq(_killer.stat_board.tempo.current, 1.0, "tempo untouched with no killer")


func test_dead_killer_pays_no_tempo() -> void:
	var victim := await _spawn_victim()
	_tm.start_turn(_killer)
	_killer.is_dead = true
	victim.die()
	assert_eq(_killer.stat_board.tempo.current, 1.0, "a dead killer collects no tempo")


func test_zero_cap_never_pays() -> void:
	_killer.stat_board.tempo.base_value = 0.0
	var victim := await _spawn_victim()
	var ap_before := _killer.stat_board.action_points.current
	_kill(victim)
	assert_eq(_killer.stat_board.action_points.current, ap_before, "cap 0 opts the entity out entirely")


func test_cap_two_pays_twice_then_stops() -> void:
	_killer.stat_board.tempo.base_value = 2.0
	_killer.stat_board.tempo.set_current(2.0)
	_killer.stat_board.action_points.base_value = 5.0
	_killer.stat_board.action_points.set_current(0.0)
	var v1 := await _spawn_victim()
	var v2 := await _spawn_victim()
	var v3 := await _spawn_victim()
	_kill(v1)
	assert_eq(_killer.stat_board.action_points.current, 1.0, "first kill under cap 2 pays out")
	_kill(v2)
	assert_eq(_killer.stat_board.action_points.current, 2.0, "second kill under cap 2 pays out")
	_kill(v3)
	assert_eq(_killer.stat_board.action_points.current, 2.0, "third kill this turn: cap exhausted, no more")


func test_blocker_victim_is_faction_less_and_still_rewards() -> void:
	# Blockers are faction-less; attitude_to reads a null faction as HOSTILE
	# (entity.gd) so no special-casing is needed here.
	var blocker := await _spawn_victim(null)
	_kill(blocker)
	assert_eq(_killer.stat_board.tempo.current, 0.0, "a faction-less blocker kill still pays tempo")


func test_award_tempo_kill_switch_suppresses_the_refund() -> void:
	_loot.award_tempo_on_kill = false
	var victim := await _spawn_victim()
	var ap_before := _killer.stat_board.action_points.current
	_kill(victim)
	assert_eq(_killer.stat_board.action_points.current, ap_before, "kill switch off -> no refund")
	assert_eq(_killer.stat_board.tempo.current, 1.0, "kill switch off -> tempo untouched")
