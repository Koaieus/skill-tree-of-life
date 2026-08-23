extends GutTest

## Smoke test for the Outcome playground panel (#539). It is an editor surface,
## so the claim it exists to prove — *the replay looks identical to the live
## run* — is an eye check. Everything under the drawing is ordinary runtime
## code, and this drives it: the panel composes, the shared builder arms the
## board, and Capture ▶ Replay round-trips to the same world.
##
## Worth having for the same reason `test_melee_sandbox_panel.gd` is: the panel
## hand-wires four systems plus a builder, and a broken wire there surfaces as
## "the tab does nothing", with no error to read.
##
## The FIXTURE is pinned elsewhere — `test_outcome_fixture_replay.gd` owns the
## committed golden and the cascade layers. This file is about the tab.

const _PANEL := preload("res://addons/outcome_playground/outcome_playground_panel.tscn")

var _panel: PanelContainer


func before_each() -> void:
	_panel = _PANEL.instantiate() as PanelContainer
	add_child_autofree(_panel)
	await get_tree().process_frame
	# Land the whole outcome on one line — this measures the record, not the
	# beat clock, and a paced cast would make the test wait out its own VFX.
	_panel._instant_toggle.button_pressed = true
	_panel._on_instant_toggled(true)


func _node(n: String) -> SkillNode:
	return _panel._builder.nodes[n] as SkillNode


## Press a panel button and wait for the QUEUE to go idle, not just for the
## button's own coroutine to return. The panel waits for *its* command
## (`command_applied` fires inside the applier's guard, exactly as
## [method BattleSystem.launch_attack] does) so it resumes while `_drain` is
## still unwinding — and a test that ended there would have GUT's autofree
## delete the panel out from under the drain, which crashes rather than fails.
func _press(button: Callable) -> void:
	@warning_ignore("redundant_await")
	await button.call()
	while _panel._applier.is_applying:
		await _panel._applier.applying_changed
	await get_tree().process_frame


func test_the_panel_composes_a_real_world_and_arms_it() -> void:
	assert_not_null(_panel._graph, "the shared builder must have produced a graph")
	assert_not_null(_panel._applier,
			"a CommandApplier is the whole point — a replay is submitted, not called")
	assert_eq(_node("d_gate").owned_by, _panel._builder.defender,
			"arm() ran: the authored ownership is real ownership")
	assert_eq(_panel._turn_manager.current_entity, _panel._builder.attacker,
			"an attack is illegal without a current entity")
	assert_null(_panel._battle.attack_plan,
			"…and nothing is armed until Capture arms it")


func test_tempo_is_wired_and_inert() -> void:
	# Decided in #539: the control exists as the seam the schedule-compiler
	# sibling plugs into, and does nothing today. Pinned so a later reader does
	# not "fix" the missing behaviour without reading that decision.
	var before: bool = _panel._battle.instant_mutation
	_panel._on_tempo_changed(2.5)
	assert_true(_panel._tempo_label.text.contains("inert"),
			"the tempo readout must say out loud that it does nothing")
	assert_eq(_panel._battle.instant_mutation, before,
			"…and moving it must not have changed the one knob that IS real")


func test_capture_then_replay_lands_the_same_world() -> void:
	# Acceptance 1's world half, through the tab rather than around it: fire a
	# live cast as the authority, then push the record it stamped back through
	# this world's own applier with no CommandLink attached.
	await _press(_panel._on_capture_pressed)
	assert_not_null(_panel._fixture, "Capture must leave a fixture in hand")
	if _panel._fixture == null:
		return
	var captured: int = _panel._last_after
	assert_ne(captured, _panel._fixture.world_fingerprint_at_capture,
			"the live cast must actually change the world")
	assert_null(_node("d_gate").owned_by, "…by killing the gate")
	var live_layers: Array = (_panel._live_layers as Array).duplicate()
	assert_eq(live_layers, [1, 1, 1] as Array[int],
			"the live cascade arrives as three BFS layers")

	await _press(_panel._on_replay_pressed)

	assert_eq(_panel._last_after, captured,
			"the replay must land the world the live run landed")
	assert_eq(_panel._last_layers, live_layers,
			"…with the same cascade layers, which is what the shatter stagger reads")
	assert_true(_panel._verdict.contains("identical"),
			"and the panel must say so: %s" % _panel._verdict)
