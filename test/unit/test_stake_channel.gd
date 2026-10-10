@tool
extends GutTest

## Staking channels: stake / extract open a channel toward a target cap that
## steps once per K owner real-turn-starts; a core ARRIVAL beyond the leash, an
## ownership loss or an explicit cancel aborts it. Geometry is derived from the
## exports (reach R), never from the literal defaults.
##
## Board (positions in units of R, all owned, core at N0):
##   N4 (0, 1.2) — one hop off N0, OUTSIDE reach
##   N0 (0, 0) - N1 (0.4, 0) - N2 (0.8, 0) - N3 (3, 0)
##   N5 (0, -0.4) — a leaf off N0, inside reach

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const R := 250.0
const _POS := [Vector2(0, 0), Vector2(0.4, 0), Vector2(0.8, 0), Vector2(3, 0),
		Vector2(0, 1.2), Vector2(0, -0.4)]

var _graph: Graph
var _alloc: AllocationSystem
var _player: Entity
var _nodes: Array[SkillNode]


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_nodes = []
	for i in _POS.size():
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.add_skill_node(sn)
		sn.position = (_POS[i] as Vector2) * R
		_nodes.append(sn)
	_graph.add_edge(_nodes[0], _nodes[1])
	_graph.add_edge(_nodes[1], _nodes[2])
	_graph.add_edge(_nodes[2], _nodes[3])
	_graph.add_edge(_nodes[0], _nodes[4])
	_graph.add_edge(_nodes[0], _nodes[5])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	_alloc.stake_reach_px = R
	_alloc.stake_leash_ratio = 2.0
	_alloc.stake_channel_turns = 2
	_alloc.extract_channel_turns = 3
	add_child_autofree(_alloc)

	_player = autofree(Entity.new())
	_player.display_name = "Player"
	_player.stat_board = TestBoards.flat_entity_board()
	_graph.add_child(_player)
	await get_tree().process_frame

	for n in _nodes:
		_alloc.force_allocate(_player, n)
	_player.core_location = _nodes[0]
	_player.stat_board.movement_points.base_value = 9.0
	_player.stat_board.movement_points.restore_to_full()


func after_each() -> void:
	_graph = null
	_alloc = null
	_player = null
	_nodes = []


func _sp() -> SkillPointStat:
	return _player.stat_board.skill_points


func _ticks(n: int) -> void:
	for i in n:
		_alloc.advance_channels(_player)


func _k_up() -> int:
	return _alloc.stake_channel_turns


func _k_down() -> int:
	return _alloc.extract_channel_turns


## Stake N1 and land it: 2-cap, fill 1, 1 SP staked.
func _landed_stake(n: SkillNode) -> void:
	assert_true(_alloc.stake(n, _player), "stake %s" % n.name)
	_ticks(_k_up())
	assert_false(n.is_channelling(), "landed")


# --- 1. stake pledges -----------------------------------------------------------

func test_stake_pledges_sp_spends_no_ap_and_opens_a_channel() -> void:
	var n := _nodes[1]
	var cur := _sp().current
	var staked := _sp().staked
	var ap := int(_player.stat_board.action_points.current)
	assert_true(_alloc.stake(n, _player))
	assert_eq(_sp().current, cur - _alloc.stake_sp_cost, "SP current pledged")
	assert_eq(_sp().staked, staked + _alloc.stake_sp_cost, "into staked")
	assert_eq(int(_player.stat_board.action_points.current), ap, "no AP")
	assert_eq(n.stake_level, 1, "cap unchanged at initiation")
	assert_eq(n.channel_target, 2, "target = cap + 1")
	assert_true(n.is_channelling())
	assert_eq(n.channel_direction(), 1)


# --- 2. lands after exactly K ticks; the tick never checks the leash -----------

func test_stake_lands_after_exactly_k_ticks() -> void:
	var n := _nodes[1]
	watch_signals(_alloc)
	_alloc.stake(n, _player)
	_ticks(_k_up() - 1)
	assert_eq(n.stake_level, 1, "one tick short: not landed")
	assert_signal_not_emitted(_alloc, "channel_ended")
	_ticks(1)
	assert_eq(n.stake_level, 2, "landed at K")
	assert_false(n.is_channelling(), "channel cleared")
	assert_eq(n.channel_progress, 0)
	assert_signal_emitted_with_parameters(_alloc, "channel_ended", [n, _player, &"landed"])


func test_every_non_landing_tick_emits_channel_progressed() -> void:
	var n := _nodes[1]
	_alloc.stake(n, _player)
	watch_signals(_alloc)
	_ticks(_k_up())
	assert_signal_emit_count(_alloc, "channel_progressed", _k_up() - 1,
			"one per tick short of the step; the landing tick steps instead")
	assert_signal_emitted_with_parameters(_alloc, "channel_progressed", [n])
	assert_signal_emit_count(_alloc, "channel_stepped", 1)


func test_tick_never_aborts_even_with_the_core_beyond_the_leash() -> void:
	var n := _nodes[1]
	_alloc.stake(n, _player)
	_player.core_location = _nodes[3]  # direct write: not an arrival
	assert_gt(_nodes[3].global_position.distance_to(n.global_position), _alloc.stake_leash_px())
	_ticks(_k_up())
	assert_eq(n.stake_level, 2, "the tick only counts progress")


# --- 3. mid-channel raise -------------------------------------------------------

func test_restake_mid_channel_raises_target_and_lands_stepwise() -> void:
	var n := _nodes[1]
	var staked := _sp().staked
	assert_true(_alloc.stake(n, _player))
	assert_true(_alloc.stake(n, _player), "raise mid-channel")
	assert_eq(n.channel_target, 3)
	assert_eq(_sp().staked, staked + 2 * _alloc.stake_sp_cost, "two pledges")
	_ticks(_k_up())
	assert_eq(n.stake_level, 2, "first step at K")
	assert_true(n.is_channelling(), "still heading to 3")
	_ticks(_k_up())
	assert_eq(n.stake_level, 3, "second step at 2K")
	assert_false(n.is_channelling())


# --- 4. leash on core arrival -----------------------------------------------------

func test_move_core_landing_beyond_the_leash_aborts() -> void:
	var n := _nodes[1]
	_alloc.stake(n, _player)
	_alloc.stake(n, _player)
	_ticks(_k_up())  # one step landed: 2, target 3
	var staked := _sp().staked
	var wounded := _sp().wounded
	watch_signals(_alloc)
	assert_true(_alloc.move_core(_player, _nodes[1]))
	assert_true(_alloc.move_core(_player, _nodes[2]))
	assert_true(n.is_channelling(), "arrivals inside the leash keep it")
	assert_true(_alloc.move_core(_player, _nodes[3]))
	assert_false(n.is_channelling(), "aborted on the outside arrival")
	assert_eq(n.stake_level, 2, "landed step kept")
	assert_eq(_sp().staked, staked - _alloc.stake_sp_cost, "pending pledge leaves staked")
	assert_eq(_sp().wounded, wounded + _alloc.stake_sp_cost, "into wounded")
	assert_signal_emitted_with_parameters(_alloc, "channel_ended", [n, _player, &"leash"])


func test_out_and_back_in_one_turn_still_aborts() -> void:
	var n := _nodes[1]
	assert_true(_alloc.move_core(_player, _nodes[1]))
	assert_true(_alloc.move_core(_player, _nodes[2]))
	_alloc.stake(n, _player)
	assert_true(_alloc.move_core(_player, _nodes[3]), "out")
	assert_true(_alloc.move_core(_player, _nodes[2]), "and back")
	assert_false(n.is_channelling(), "the intermediate arrival is checked")


# --- 5. ownership loss ------------------------------------------------------------

func _assert_ownership_abort(n: SkillNode, strip: Callable) -> void:
	watch_signals(_alloc)
	assert_true(_alloc.stake(n, _player))
	var wounded := _sp().wounded
	strip.call()
	assert_null(n.owned_by)
	assert_eq(n.channel_target, 0, "target cleared")
	assert_eq(n.channel_progress, 0)
	assert_eq(_sp().wounded, wounded + _alloc.stake_sp_cost, "the previous owner is wounded")
	assert_signal_emitted_with_parameters(_alloc, "channel_ended", [n, _player, &"ownership"])
	assert_signal_emit_count(_alloc, "channel_ended", 1)


func test_force_deallocate_aborts_and_wounds_previous_owner() -> void:
	var n := _nodes[5]
	_assert_ownership_abort(n, func() -> void: _alloc.force_deallocate(n))


func test_deallocate_aborts_and_wounds_previous_owner() -> void:
	var n := _nodes[5]
	_assert_ownership_abort(n, func() -> void: assert_true(_alloc.deallocate(n, _player)))


func test_owner_death_strip_aborts_and_wounds_previous_owner() -> void:
	var n := _nodes[5]
	_assert_ownership_abort(n, func() -> void: _alloc.deallocate_all_owned(_player))


# --- 6. extract ---------------------------------------------------------------------

func test_extract_pays_dp_now_and_lands_the_exchange_after_k() -> void:
	var n := _nodes[1]
	_landed_stake(n)
	assert_true(_alloc.allocate(n, _player), "fill to 2/2")
	var dp := int(_player.stat_board.deallocation_points.current)
	var cur := _sp().current
	var staked := _sp().staked
	var wounded := _sp().wounded
	assert_true(_alloc.extract(n, _player))
	assert_eq(int(_player.stat_board.deallocation_points.current), dp - 1, "1 DP at initiation")
	assert_eq([_sp().current, _sp().staked, _sp().wounded], [cur, staked, wounded], "no SP moves yet")
	assert_eq(n.channel_target, 1)
	assert_eq(n.channel_direction(), -1)
	_ticks(_k_down() - 1)
	assert_eq(n.stake_level, 2, "one tick short")
	_ticks(1)
	assert_eq(n.stake_level, 1)
	assert_eq(n.allocation_level, 1, "fill steps down with the cap")
	assert_eq(_sp().staked, staked - _alloc.extract_sp_refund)
	assert_eq(_sp().wounded, wounded + _alloc.extract_sp_refund)
	assert_eq(_sp().current, cur + 1, "the displaced fill is refunded")
	assert_eq(int(_player.stat_board.deallocation_points.current), dp - 1, "1 DP per step, never 2")


func test_extract_abort_forfeits_dp_and_moves_no_sp() -> void:
	var n := _nodes[1]
	_landed_stake(n)
	var dp := int(_player.stat_board.deallocation_points.current)
	var buckets := [_sp().current, _sp().staked, _sp().wounded]
	assert_true(_alloc.extract(n, _player))
	assert_true(_alloc.cancel_channel(n, _player))
	assert_eq(n.stake_level, 2)
	assert_false(n.is_channelling())
	assert_eq(int(_player.stat_board.deallocation_points.current), dp - 1, "DP forfeited")
	assert_eq([_sp().current, _sp().staked, _sp().wounded], buckets, "no SP moved")


# --- 7. denials -------------------------------------------------------------------

func test_reach_is_euclidean_not_hops() -> void:
	assert_eq(_alloc.stake_denial(_nodes[2], _player), &"", "two hops, inside the radius")
	assert_eq(_alloc.stake_denial(_nodes[4], _player), &"stake_denied_not_adjacent",
			"one hop, beyond the radius")
	_nodes[4].stake_level = 2
	assert_eq(_alloc.extract_denial(_nodes[4], _player), &"extract_denied_not_adjacent")


func test_opposite_verb_on_a_channelling_node_is_denied() -> void:
	var up := _nodes[1]
	_alloc.stake(up, _player)
	assert_eq(_alloc.extract_denial(up, _player), &"extract_denied_channelling")
	var down := _nodes[2]
	_landed_stake(down)
	assert_true(_alloc.extract(down, _player))
	assert_eq(_alloc.stake_denial(down, _player), &"stake_denied_channelling")


func test_stake_denials_count_the_target_and_never_mention_ap() -> void:
	var n := _nodes[1]
	_player.stat_board.action_points.set_current(0.0)
	n.stake_level = n.stake_ceiling - 1
	assert_eq(_alloc.stake_denial(n, _player), &"", "AP is no gate")
	assert_true(_alloc.stake(n, _player))
	assert_eq(_alloc.stake_denial(n, _player), &"stake_denied_at_ceiling", "the target counts")
	_alloc.stake_sp_cost = int(_sp().current) + 1
	assert_eq(_alloc.stake_denial(_nodes[2], _player), &"stake_denied_no_sp")


# --- 8. node-local ceiling --------------------------------------------------------

func test_node_local_ceiling_two_denies_the_third_level() -> void:
	var n := _nodes[1]
	var m := StatModifier.new()
	m.stat_id = &"stake_ceiling"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = -1.0
	n.add_local_modifier(m)
	assert_eq(n.stake_ceiling, 2)
	_landed_stake(n)
	assert_eq(_alloc.stake_denial(n, _player), &"stake_denied_at_ceiling")


func test_default_ceiling_denies_the_fourth_level() -> void:
	var n := _nodes[1]
	n.stake_level = 2
	assert_eq(_alloc.stake_denial(n, _player), &"")
	n.stake_level = 3
	assert_eq(_alloc.stake_denial(n, _player), &"stake_denied_at_ceiling")


# --- 9. the tick hook -------------------------------------------------------------

func test_tick_runs_on_real_turn_started_only_for_the_owner() -> void:
	var tm: TurnManager = autofree(TurnManager.new())
	_alloc.turn_manager = tm
	var n := _nodes[1]
	_alloc.stake(n, _player)
	tm.turn_started.emit(_player)
	assert_eq(n.channel_progress, 0, "turn_started (resync cursor) is not a tick")
	var other: Entity = autofree(Entity.new())
	tm.real_turn_started.emit(other)
	assert_eq(n.channel_progress, 0, "another entity's turn is not a tick")
	tm.real_turn_started.emit(_player)
	assert_eq(n.channel_progress, 1, "one served turn, one tick")


# --- 11. leash ≥ reach by construction ----------------------------------------------

func test_leash_never_shorter_than_reach() -> void:
	for reach in [1.0, 100.0, 250.0, 777.0]:
		for ratio in [0.0, 0.5, 0.99, 1.0, 2.0, 3.5]:
			_alloc.stake_reach_px = reach
			_alloc.stake_leash_ratio = ratio
			assert_gte(_alloc.stake_leash_px(), reach, "reach %s ratio %s" % [reach, ratio])


# --- 12. cancel ---------------------------------------------------------------------

func test_cancel_stake_wounds_the_pledge() -> void:
	var n := _nodes[1]
	_alloc.stake(n, _player)
	var staked := _sp().staked
	var wounded := _sp().wounded
	watch_signals(_alloc)
	assert_true(_alloc.can_cancel_channel(n, _player))
	assert_true(_alloc.cancel_channel(n, _player))
	assert_eq(_sp().staked, staked - _alloc.stake_sp_cost)
	assert_eq(_sp().wounded, wounded + _alloc.stake_sp_cost)
	assert_eq(n.stake_level, 1)
	assert_signal_emitted_with_parameters(_alloc, "channel_ended", [n, _player, &"cancelled"])


func test_cancel_has_no_reach_gate() -> void:
	var n := _nodes[1]
	_alloc.stake(n, _player)
	_player.core_location = _nodes[3]
	assert_eq(_alloc.cancel_channel_denial(n, _player), &"")


func test_cancel_denials() -> void:
	assert_eq(_alloc.cancel_channel_denial(_nodes[1], _player), &"cancel_denied_idle")
	assert_false(_alloc.cancel_channel(_nodes[1], _player))
	_alloc.stake(_nodes[1], _player)
	var other: Entity = autofree(Entity.new())
	assert_eq(_alloc.cancel_channel_denial(_nodes[1], other), &"cancel_denied_not_owned")


func test_cancel_command_round_trips_the_codec() -> void:
	var back := CommandCodec.from_dict(CancelChannelCommand.new(4, 9).to_dict())
	assert_true(back is CancelChannelCommand)
	assert_eq((back as CancelChannelCommand).node_id, 9)
	assert_eq(back.entity_id, 4)


# --- 13. signals + fraction ---------------------------------------------------------

func test_channel_signals_and_fraction() -> void:
	var n := _nodes[1]
	watch_signals(_alloc)
	assert_eq(_alloc.channel_fraction(n), 0.0, "idle")
	_alloc.stake(n, _player)
	assert_signal_emit_count(_alloc, "channel_changed", 1, "start")
	_alloc.stake(n, _player)
	assert_signal_emit_count(_alloc, "channel_changed", 2, "raise")
	var k := _k_up()
	for i in k - 1:
		assert_almost_eq(_alloc.channel_fraction(n), float(i) / k, 0.0001)
		_ticks(1)
	assert_almost_eq(_alloc.channel_fraction(n), float(k - 1) / k, 0.0001)
	_ticks(1)
	assert_signal_emitted_with_parameters(_alloc, "channel_stepped", [n, 1])
	assert_signal_not_emitted(_alloc, "channel_ended", "still heading to 3")
	_ticks(k)
	assert_signal_emit_count(_alloc, "channel_stepped", 2)
	assert_signal_emit_count(_alloc, "channel_ended", 1, "exactly once")
	assert_eq(_alloc.channel_fraction(n), 0.0)
