extends GutTest

## The act gate as a function of (AP pool, turn cursor) — no scene (#983).
##
## The integration keeper (`test/integration/scenes/test_act_gate_across_turns.gd`)
## drives `dev_sandbox.tscn` because that scene IS the reproduction of the
## a628636 regression: a scene-wired `player` export bound
## [PlayerInputController._set_player] to a board that `Entity._ready` then
## replaced with a `duplicate(true)`, and an early return in the setter made
## `GameRoot.bind_player`'s re-assert a no-op, so PIC listened to a discarded
## pool for the rest of the run. The swap is gone since #1031 (the setter
## takes its private copy at assignment; the board is sealed after bring-up),
## so the fixture now pins the opposite: the board PIC bound to pre-tree IS
## the live one. This file rebuilds that ordering by hand — `player` assigned
## BEFORE the entity enters the tree, then re-asserted after bring-up — and
## drives the cursor straight through [TurnManager], so a wrong emission is a
## wrong emission here and not a paced AI turn.
##
## Since #957 the gate has no AP clause (a 0-AP volley must stay launchable),
## so "the gate says true on the player's turn" holds whichever pool PIC
## listens to. What the live subscription still buys — and what these
## asserts pin — is that `player_can_act_changed` fires on every change of
## the LIVE pool (`can_afford`'s contract: a Launch button re-asks both), the
## turn-start refill included.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _tm: TurnManager
var _ctl: PlayerInputController
var _player: Entity
var _enemy: Entity
var _pre_tree_board: StatBoard
## Reference type on purpose — a lambda captures a local `bool`/`int` by value.
var _emissions: Array[bool]
## `_emissions.size()` once the enemy's turn has ended — the cursor is about
## to land on the player, so everything appended after this mark is the
## player's turn (re)starting: PIC's `turn_started` emission, then the
## refill's. (Recorded on `turn_ended`, not `turn_started`: the entities'
## own `turn_started` handlers were connected before this test's, so a mark
## taken there would already sit past the refill.)
var _size_before_player_turn_start: int


func _make_entity(ent_name: String) -> Entity:
	var e := Entity.new()
	e.name = ent_name
	e.display_name = ent_name
	e.stat_board = _BOARD.duplicate(true)
	return e


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	# TurnManager enters the tree before either entity: `Entity.initialize`
	# finds it by group.
	_tm = autofree(TurnManager.new())
	add_child(_tm)

	var alloc := AllocationSystem.new()
	alloc.graph = _graph
	alloc.turn_manager = _tm
	add_child_autofree(alloc)

	# PIC enters the tree before the entities so its `turn_started` handler
	# runs BEFORE `Entity._on_turn_started` refills AP — the same order the
	# regression story depends on: gate computed first, refill second.
	_ctl = PlayerInputController.new()
	_ctl.graph = _graph
	_ctl.allocation_system = alloc
	_ctl.turn_manager = _tm
	add_child_autofree(_ctl)

	# The scene-wired ordering: `player` assigned before the entity enters the
	# tree — the board it binds to must survive bring-up.
	_player = autofree(_make_entity("Player"))
	_ctl.player = _player
	_pre_tree_board = _player.stat_board
	_graph.entities_container.add_child(_player)
	# `GameRoot.bind_player`'s idempotent re-assert — the call the early
	# return silently swallowed.
	_ctl.player = _player

	_enemy = autofree(_make_entity("Enemy"))
	_graph.entities_container.add_child(_enemy)

	await get_tree().process_frame
	assert_same(_player.stat_board, _pre_tree_board,
			"the board bound before add_child is the live board after bring-up (#1031)")

	_tm.start_turn(_player)
	_emissions = []
	_ctl.player_can_act_changed.connect(func(can_act: bool) -> void: _emissions.append(can_act))
	_tm.turn_ended.connect(func(e: Entity) -> void:
		if e == _enemy:
			_size_before_player_turn_start = _emissions.size())


func test_pic_listens_to_the_live_ap_pool_not_the_discarded_board() -> void:
	var ap: PoolStat = _player.stat_board.action_points
	assert_true(ap.current_changed.is_connected(_ctl._on_ap_changed),
			"PIC must be subscribed to the board Entity._ready actually kept")


func test_a_change_on_the_live_pool_re_emits_the_gate() -> void:
	var ap: PoolStat = _player.stat_board.action_points
	ap.set_current(0.0)
	assert_eq(_emissions, [true] as Array[bool],
			"an AP change on the live pool must re-emit the (still open) gate")


func test_gate_re_emits_true_after_a_turn_that_spent_all_ap() -> void:
	_player.stat_board.action_points.set_current(0.0)
	_hand_the_turn_around()
	assert_true(_emissions.has(false), "the gate must have closed while the enemy held the turn")
	assert_true(_emissions.back(),
			"last gate emission must be true, or the command tray stays dead (%s)"
			% [_emissions])


func test_turn_entered_with_ap_spent_emits_true_again_on_the_refill() -> void:
	_player.stat_board.action_points.set_current(0.0)
	_hand_the_turn_around()
	# PIC's `turn_started` emission is the first; the refill's `current_changed`
	# on the LIVE pool is the second. Listening to the discarded board loses
	# the second one.
	assert_eq(_emissions.slice(_size_before_player_turn_start), [true, true] as Array[bool],
			"turn_started emission, then the refill's (%s)" % [_emissions])


func test_gate_re_emits_true_after_a_turn_that_spent_no_ap() -> void:
	_hand_the_turn_around()
	assert_true(_emissions.back(), "last gate emission must be true (%s)" % [_emissions])


## Straight through the cursor: end the player's turn, the enemy gets it
## (`_tick_until_ready` breaks the tie away from the entity that just acted),
## end that, and the player has it back — turn 2, so upkeep refills AP.
func _hand_the_turn_around() -> void:
	_tm.end_turn()
	assert_eq(_tm.current_entity, _enemy, "fixture: the enemy should hold the turn")
	_tm.end_turn()
	assert_eq(_tm.current_entity, _player, "fixture: the turn should be back with the player")
	assert_true(_ctl.can_player_act(), "fixture: the gate's inputs should all be open")
