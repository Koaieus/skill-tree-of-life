extends GutTest

## The act gate must re-open on the player's next turn, on a REAL level.
##
## `AttackModeBar` (and with it the whole command tray) is gated purely off
## [signal PlayerInputController.player_can_act_changed] — it never polls
## `can_player_act()`. So "the gate is true again" is not the property that
## matters; "the gate EMITTED true again" is, and the two came apart:
##
##   * a628636 gave `_set_player` a `player == value` early return, which also
##     skipped the AP re-subscription, and
##   * `Entity._ready` replaces `stat_board` with a `duplicate(true)` AFTER a
##     scene-wired `player` export has already been assigned,
##
## so PIC sat listening to a discarded pool. On `turn_started` the gate is
## computed BEFORE `Entity._on_turn_started` refills AP (same synchronous
## emit, PIC's handler runs first), so a turn entered with AP spent emits
## `false` and the refill's `current_changed` — the only thing that would
## correct it — never arrived. Tray dead for the rest of the run.
##
## Drives `dev_sandbox.tscn` because that scene IS the reproduction: a
## procgen sandbox spawns its player during `_setup_level`, after the board
## swap, and never sees this.

const _SANDBOX := preload("res://scenes/dev_sandbox.tscn")

var _root: GameRoot
var _ctl: PlayerInputController
var _emissions: Array[bool]


func before_each() -> void:
	_root = _SANDBOX.instantiate()
	add_child_autofree(_root)
	_ctl = _root.input_ctl
	for _i in 60:
		await wait_physics_frames(1)
		if _root.turn_manager.current_entity != null:
			break
	assert_eq(_root.turn_manager.current_entity, _root.player,
			"fixture: the player should hold the first turn")
	_emissions = []
	_ctl.player_can_act_changed.connect(func(can_act: bool): _emissions.append(can_act))


func test_pic_listens_to_the_live_ap_pool_not_a_discarded_board() -> void:
	var ap: PoolStat = _root.player.stat_board.action_points
	assert_true(ap.current_changed.is_connected(_ctl._on_ap_changed),
			"PIC must be subscribed to the board Entity._ready actually kept")


func test_gate_reopens_after_a_turn_that_spent_all_ap() -> void:
	var ap: PoolStat = _root.player.stat_board.action_points
	ap.set_current(0.0)
	await _hand_the_turn_around()
	assert_true(_emissions.back(),
			"last gate emission must be true, or the command tray stays dead (%s)"
			% [_emissions])


func test_gate_reopens_after_a_turn_that_spent_no_ap() -> void:
	await _hand_the_turn_around()
	assert_true(_emissions.back(),
			"last gate emission must be true (%s)" % [_emissions])


## End the turn through the same door ActionCluster uses post-#510 — the
## applier, not `TurnManager.end_turn()` — then let the AI hand it back.
func _hand_the_turn_around() -> void:
	_ctl.command_applier.submit(EndTurnCommand.new(_root.player.entity_id))
	for _i in 600:
		await wait_physics_frames(1)
		if _root.turn_manager.current_entity == _root.player:
			break
	await wait_physics_frames(3)
	assert_eq(_root.turn_manager.current_entity, _root.player,
			"fixture: the turn should be back with the player")
	assert_true(_ctl.can_player_act(), "fixture: the gate's inputs should all be open")
