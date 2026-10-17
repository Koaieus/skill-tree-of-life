extends GutTest
## The inner-ring modal over a real composition root: `HudRoot.open_ring`
## raises it without pausing the tree, a confirmed buyable cell submits one
## [SpendRingCellCommand], a locked cell keeps confirm dead and says why, and
## the modal stays up — read-only once the points run out.

const _GAME_ROOT := preload("res://test/support/route_probe_game_root.tscn")
const _SKILL_NODE := preload("res://skill_node/skill_node.tscn")
const _BALANCED := preload("res://entity/core/balanced_core.tres")

var _root: RouteProbeGameRoot
var _player: Entity


func before_each() -> void:
	_root = _GAME_ROOT.instantiate()
	_root.get_node("%TurnManager").opens_first_turn = false
	_root.route_to_meta_on_run_end = false
	add_child_autofree(_root)
	await wait_physics_frames(2)
	var a := _SKILL_NODE.instantiate() as SkillNode
	a.name = "A"
	_root.graph.add_skill_node(a)
	var b := _SKILL_NODE.instantiate() as SkillNode
	b.name = "B"
	b.position = Vector2(120, 0)
	_root.graph.add_skill_node(b)
	_root.graph.add_edge(a, b)
	_player = _root.spawn_entity("P1", Color.CYAN, a, _BALANCED)
	_root.bind_player(_player)
	await wait_physics_frames(1)


func after_each() -> void:
	GameSession.end()


## Earn `k` ring points the way play does: by reaching milestone levels.
func _earn(k: int) -> void:
	var target := int(_player.level) + k * _player.milestone_level_interval
	target -= target % _player.milestone_level_interval
	while int(_player.level) < target:
		_player._on_xp_replenished()


func _modal() -> RingModal:
	return _root.hud_root.ring_modal


func _body() -> RingBody:
	return _modal().body()


func _confirm_button() -> Button:
	return _modal().get_node("%ConfirmButton")


func _drained() -> void:
	var applier := _root.command_applier
	while applier.is_applying:
		await applier.applying_changed
	await wait_physics_frames(1)


func _open() -> void:
	_root.hud_root.open_ring(_player)
	await wait_physics_frames(1)


func test_open_ring_shows_the_modal_without_pausing() -> void:
	_earn(1)
	await _open()
	assert_true(_modal().visible, "open_ring raises the ring modal")
	assert_false(get_tree().paused, "a modal never pauses the tree")
	assert_not_null(_body(), "the modal presents a RingBody")


## As a peer: the confirm goes up as exactly one intent, and the cell stays
## pending (confirm dead) until the host's confirmed command lands. A
## [SpendRingCellCommand] bypasses the authority's queue, so the intent is the
## one door that sees the command itself.
func test_confirming_a_buyable_t1_submits_one_command() -> void:
	_earn(2)
	await _open()
	var applier := _root.command_applier
	applier.is_authority = false
	watch_signals(applier)
	_body().select(&"BleedingT1")
	assert_true(_body().is_selection_valid(), "a funded, linked T1 is buyable")
	assert_false(_confirm_button().disabled)
	_confirm_button().pressed.emit()
	await wait_physics_frames(1)
	assert_signal_emit_count(applier, "intent_submitted", 1, "one command per confirm")
	var params: Variant = get_signal_parameters(applier, "intent_submitted")
	var cmd: SpendRingCellCommand = null
	if params != null:
		cmd = params[0] as SpendRingCellCommand
	assert_not_null(cmd, "the command is a SpendRingCellCommand")
	if cmd != null:
		assert_eq(cmd.cell, &"BleedingT1")
		assert_eq(cmd.entity_id, _player.entity_id)
	assert_false(_player.ring_spent.has(&"BleedingT1"), "the UI never mutates the ring")
	assert_true(_modal().visible, "a buy does not close the modal")
	assert_true(_confirm_button().disabled, "pending until the confirmed command lands")
	applier.is_authority = true


func test_with_points_left_the_modal_stays_open_for_another_buy() -> void:
	_earn(2)
	await _open()
	_body().select(&"BleedingT1")
	_confirm_button().pressed.emit()
	await _drained()
	assert_true(_player.ring_spent.has(&"BleedingT1"), "the authority applied it")
	assert_true(_modal().visible, "with a point left the modal stays open")
	_body().select(&"WeaknessT1")
	assert_true(_body().is_selection_valid(), "the next linked cell is buyable")


func test_a_locked_cell_cannot_be_confirmed_and_says_why() -> void:
	_earn(2)
	await _open()
	_body().select(&"PoisonT2")
	assert_false(_body().is_selection_valid(), "an unlinked cell is not buyable")
	assert_true(_confirm_button().disabled)
	assert_string_contains(_body().status_text().to_lower(), "linked")


func test_at_zero_points_the_modal_stays_open_read_only() -> void:
	_earn(1)
	await _open()
	_body().select(&"BleedingT1")
	_confirm_button().pressed.emit()
	await _drained()
	assert_true(_player.ring_spent.has(&"BleedingT1"))
	assert_true(_modal().visible, "at zero points the modal stays open to review")
	_body().select(&"WeaknessT1")
	assert_false(_body().is_selection_valid(), "no points: nothing is buyable")
	assert_true(_confirm_button().disabled, "confirm is disabled at zero")
	assert_string_contains(_body().status_text().to_lower(), "point")
