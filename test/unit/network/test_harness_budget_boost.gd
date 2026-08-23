extends GutTest

## The multiplayer harness's budget boost, and the two things that must stay
## true about its gate.
##
## `mp_dev_sandbox._boost_autopilot_budget` fattens Red to 30 SP / 12 AP / 10 DP
## / 200 mana so ONE turn can pay for `--autopilot`'s whole verb sweep. It used
## to run unconditionally, so launching the pair from the sandbox host's
## Multiplayer tab to actually *play* it handed a human a Red with 24-odd
## unspent skill points and 200-plus mana — which reads as a stat-system bug,
## not as a test fixture, because nothing on screen says a sweep flag exists.
##
## Gating it is only half the fix, and the other half is the one a future
## refactor is likely to undo: the flag has to reach BOTH peers.
## [method CommandApplier._apply_mass_allocate] re-derives affordability from the
## RECEIVING peer's own board (#458), so a host-only boost desyncs the first
## budget-gated verb that crosses — which is exactly why the boost was
## unconditional to begin with. The launcher's own rule is "each flag goes to the
## one role that can act on it"; `--autopilot` is its single deliberate
## exception, and an exception with no test is an exception waiting to be tidied
## away.

const MP_SANDBOX := "res://scenes/dev/mp_dev_sandbox.tscn"
const MP_PANEL := "res://addons/mp_sandbox/mp_sandbox_panel.tscn"

## The four the boost writes. Duplicated from the scene on purpose: a test that
## read them back off the same method it is checking would pass no matter what
## that method did.
const BOOSTED_SKILL_POINTS := 30.0
const BOOSTED_ACTION_POINTS := 12.0
const BOOSTED_DEALLOC_POINTS := 10.0
const BOOSTED_MANA := 200.0


## A harness whose `_ready` has run to completion — `_setup_level` is past two
## awaits and the boost decision is made inside it.
func _live_harness() -> Node:
	var root: Node = preload(MP_SANDBOX).instantiate()
	add_child_autofree(root)
	await wait_frames(8)
	return root


func _red_board(root: Node) -> StatBoard:
	var red := root.get_node_or_null(^"Graph/Entities/Player") as Entity
	assert_not_null(red, "the harness still has Red at Graph/Entities/Player")
	return red.stat_board if red != null else null


# --- the gate ---------------------------------------------------------------

func test_a_plain_launch_leaves_red_on_the_board_the_scene_authored() -> void:
	# No `--autopilot` on the command line, which is every launch from the tab
	# with the toggle off, and every hand-driven `--role=solo` run.
	var root: Node = await _live_harness()
	var board := _red_board(root)
	assert_not_null(board, "Red has a stat board")
	if board == null:
		return

	assert_ne(board.skill_points.base_value, BOOSTED_SKILL_POINTS,
			"Red must not be carrying the autopilot skill-point boost — " \
			+ "a human launched this to play it, not to sweep it")
	assert_ne(board.action_points.base_value, BOOSTED_ACTION_POINTS,
			"nor the action-point boost")
	assert_ne(board.deallocation_points.base_value, BOOSTED_DEALLOC_POINTS,
			"nor the deallocation-point boost")
	assert_ne(board.mana.base_value, BOOSTED_MANA,
			"nor the mana boost — 200 base mana is the tell people actually notice")


func test_the_boost_itself_still_does_what_the_sweep_needs() -> void:
	# The other half: gating it must not have left a dead method behind. If this
	# goes red the sweep silently starves and every verb after the first few logs
	# SKIPPED — unaffordable, which reads like a topology problem.
	var root: Node = await _live_harness()
	var board := _red_board(root)
	if board == null:
		return

	root._boost_autopilot_budget()

	assert_eq(board.skill_points.base_value, BOOSTED_SKILL_POINTS)
	assert_eq(board.action_points.base_value, BOOSTED_ACTION_POINTS)
	assert_eq(board.deallocation_points.base_value, BOOSTED_DEALLOC_POINTS)
	assert_eq(board.mana.base_value, BOOSTED_MANA)


# --- the half that has to reach both peers ----------------------------------

func _panel() -> PanelContainer:
	var panel: PanelContainer = preload(MP_PANEL).instantiate()
	add_child_autofree(panel)
	await wait_frames(1)
	return panel


func test_the_launcher_sends_the_sweep_flag_to_both_peers() -> void:
	var panel: PanelContainer = await _panel()
	panel.get_node("%AutopilotToggle").button_pressed = true

	var host: PackedStringArray = panel.build_args(NetworkTransport.Role.HOST, MP_SANDBOX)
	var client: PackedStringArray = panel.build_args(NetworkTransport.Role.CLIENT, MP_SANDBOX)

	assert_true(Array(host).has("--autopilot"), "the host sweeps, so it gets the flag")
	assert_true(Array(client).has("--autopilot"),
			"and so does the CLIENT — not to sweep (it is not the authority) but " \
			+ "because the flag gates Red's budget boost, and a boost that lands " \
			+ "on one peer only desyncs the first budget-gated verb that crosses")


func test_the_launcher_sends_no_sweep_flag_when_the_toggle_is_off() -> void:
	var panel: PanelContainer = await _panel()
	panel.get_node("%AutopilotToggle").button_pressed = false

	var host: PackedStringArray = panel.build_args(NetworkTransport.Role.HOST, MP_SANDBOX)
	var client: PackedStringArray = panel.build_args(NetworkTransport.Role.CLIENT, MP_SANDBOX)

	assert_false(Array(host).has("--autopilot"), "off means off")
	assert_false(Array(client).has("--autopilot"), "on both")


func test_the_probe_flag_by_contrast_stays_client_only() -> void:
	# The rule `--autopilot` is the exception TO. Without this, "send it to both"
	# is easy to over-apply to the next flag someone adds.
	var panel: PanelContainer = await _panel()
	panel.get_node("%ProbeToggle").button_pressed = true

	var host: PackedStringArray = panel.build_args(NetworkTransport.Role.HOST, MP_SANDBOX)
	var client: PackedStringArray = panel.build_args(NetworkTransport.Role.CLIENT, MP_SANDBOX)

	assert_false(Array(host).has("--probe"),
			"a host receives nothing to re-derive, so the probe there measures an empty table")
	assert_true(Array(client).has("--probe"), "the mirroring peer is the one that can measure")
