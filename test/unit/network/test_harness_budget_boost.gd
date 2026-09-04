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

## The scene `mp_dev_sandbox` inherits, and the baseline it is measured against.
## Read from a live instance rather than hardcoded, because Red's opening board is
## not the four `.tscn` sub-resource values: `skill_points` opens at 8 against an
## authored 3, since [method AllocationSystem.register_scene_authored_ownership]
## calls `claim(1)` for every scene-authored owned node and
## [method SkillPointStat.claim] adds to `base_value`. A literal here would be a
## number nobody could re-derive, and it would go stale the first time someone
## authored a sixth owned node onto Red.
##
## Comparing the two scenes is also the STRONGER assertion. "Red's base is not
## 30" passes again the moment someone re-tunes the boost to 40 and leaves it
## un-gated — same bug, new constants. "The harness gives Red exactly the board
## the plain sandbox does" cannot. `skill_points` is the one pool that can no
## longer be held to it — see [constant COMPARABLE_POOLS].
const DEV_SANDBOX := "res://scenes/dev_sandbox.tscn"

## The pools the boost writes.
const BUDGET_POOLS: Array[StringName] = [
	&"skill_points", &"action_points", &"deallocation_points", &"mana",
]

## The subset whose `base_value` two live levels can be compared on. Everything
## but `skill_points`: since dev_sandbox adopted `default_entity_board.tres`
## (the board that carries `level`), turn-start XP levels Red and a level MINTS
## skill points into `base_value` — and whether a given level's Red gets that
## upkeep depends on which TurnManager holds the group when his entity binds
## ([method Entity._find_turn_manager] is a global group lookup, so two levels
## in one process do not both get one). The other three are REFILL/ADD pools
## whose `base_value` no amount of play moves. `skill_points` keeps its own
## assertion below, against the boost constant.
const COMPARABLE_POOLS: Array[StringName] = [
	&"action_points", &"deallocation_points", &"mana",
]


## A level whose `_ready` has run to completion — it is a coroutine, and
## `_setup_level` (where the boost decision is made) sits past two of its awaits.
func _live_scene(path: String) -> Node:
	var root: Node = load(path).instantiate()
	add_child_autofree(root)
	await wait_frames(8)
	return root


func _live_harness() -> Node:
	return await _live_scene(MP_SANDBOX)


func _red_board(root: Node) -> StatBoard:
	var red := root.get_node_or_null(^"Graph/Entities/Player") as Entity
	assert_not_null(red, "the harness still has Red at Graph/Entities/Player")
	return red.stat_board if red != null else null


# --- the gate ---------------------------------------------------------------

func test_a_plain_launch_leaves_red_on_the_board_the_plain_sandbox_gives_him() -> void:
	# No `--autopilot` on the command line, which is every launch from the tab
	# with the toggle off, and every hand-driven `--role=solo` run.
	var harness: Node = await _live_harness()
	var plain: Node = await _live_scene(DEV_SANDBOX)
	var boosted := _red_board(harness)
	var baseline := _red_board(plain)
	assert_not_null(boosted, "the harness's Red has a stat board")
	assert_not_null(baseline, "the plain sandbox's Red has one too")
	if boosted == null or baseline == null:
		return

	for id in COMPARABLE_POOLS:
		assert_eq(boosted.get_stat(id).base_value, baseline.get_stat(id).base_value,
				"%s: adding a network role must not change Red's budget — " % id \
				+ "a human launched this to play it, not to sweep it")
	# The pool the gate is actually about, asserted against the boost rather than
	# against the other level — see COMPARABLE_POOLS for why it can't be compared.
	assert_ne(boosted.skill_points.base_value, BOOSTED_SKILL_POINTS,
			"an unswept launch must not get the sweep's skill points")


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


## Both orderings of the mismatch, because the launcher's warning is built by
## comparing two booleans and the natural way to word that — negating one clause —
## is right in one direction and reads as "neither has it" in the other. A
## warning that tells a human nothing is wrong is the same as no warning, and
## this guardrail exists precisely because a mismatched pair produces a LYING
## `DIVERGED` line.
##
## Driven straight through the seam rather than by spawning: `_pids` and
## `_sweeping_by_pid` are what `_launch` would have left behind.
func _warning_text_for(sibling_swept: bool, this_launch_sweeps: bool) -> String:
	var panel: PanelContainer = await _panel()
	panel._pids = [4242] as Array[int]
	panel._sweeping_by_pid = {4242: sibling_swept}
	panel._warn_if_the_pair_would_be_asymmetric(this_launch_sweeps)
	return (panel.get_node("%Log") as RichTextLabel).get_parsed_text()


func test_the_launcher_flags_a_mismatched_pair_in_both_directions() -> void:
	# Asserted as "this pid, that state", not merely "both words appear" — the
	# latter passes just as happily with the two sides swapped, which is a
	# warning that sends someone to relaunch the half that was already right.
	var swept_first: String = await _warning_text_for(true, false)
	assert_string_contains(swept_first, "pid 4242 has --autopilot=ON")
	assert_string_contains(swept_first, "this launch has --autopilot=OFF")

	var swept_second: String = await _warning_text_for(false, true)
	assert_string_contains(swept_second, "pid 4242 has --autopilot=OFF")
	assert_string_contains(swept_second, "this launch has --autopilot=ON")


func test_a_matched_pair_draws_no_warning_either_way() -> void:
	# The other half: a guardrail that cries wolf on every launch gets ignored,
	# and "Launch both" is the common path.
	var both_off: String = await _warning_text_for(false, false)
	assert_false(both_off.contains("mismatched"), "both off is a matched pair")

	var both_on: String = await _warning_text_for(true, true)
	assert_false(both_on.contains("mismatched"), "and so is both on")


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


## --- Rungs 3/4: the shipped lobby route (#754) --------------------------------
##
## The launcher's third row takes NO scene. Everything below is one property:
## the command line it builds must be the one `MetaRoot`'s `--lobby=` driver
## reads, because those two files are the only agreement there is — a scene
## positional or a `--role=` here produces a process that boots the menu and
## then sits on it forever, which looks exactly like a hung link.


func test_the_lobby_route_passes_no_scene() -> void:
	var panel: PanelContainer = await _panel()

	var host: PackedStringArray = panel.build_args(
			NetworkTransport.Role.HOST, panel.LOBBY_ROUTE)

	var separator := Array(host).find("--")
	assert_gt(separator, 0, "there is still a `--`")
	for arg in Array(host).slice(0, separator):
		assert_false(String(arg).ends_with(".tscn"),
				"no scene before the separator — rungs 3/4 boot `run/main_scene`")


func test_the_lobby_route_asks_for_a_lobby_role_not_a_scene_role() -> void:
	var panel: PanelContainer = await _panel()

	var host: PackedStringArray = panel.build_args(
			NetworkTransport.Role.HOST, panel.LOBBY_ROUTE)
	var client: PackedStringArray = panel.build_args(
			NetworkTransport.Role.CLIENT, panel.LOBBY_ROUTE)

	assert_true(Array(host).has("--lobby=host"))
	assert_true(Array(client).has("--lobby=client"))
	assert_false(Array(host).has("--role=host"),
			"`--role` is what a sandbox SCENE reads; nothing on this route would see it")


## The same toggle, a different word — and the word has to be the one
## `HarnessFlags.AUTOPLAY` names, or the pair plays nothing and the run never
## ends.
func test_the_autopilot_toggle_spells_itself_autoplay_on_the_lobby_route() -> void:
	var panel: PanelContainer = await _panel()
	panel.get_node("%AutopilotToggle").button_pressed = true

	var host: PackedStringArray = panel.build_args(
			NetworkTransport.Role.HOST, panel.LOBBY_ROUTE)
	var client: PackedStringArray = panel.build_args(
			NetworkTransport.Role.CLIENT, panel.LOBBY_ROUTE)

	assert_true(Array(host).has("--autoplay"), "the host is the one that hands the seats over")
	assert_true(Array(client).has("--autoplay"),
			"and the client, which reads it for the zero AI turn delay and its own verdict line")
	assert_false(Array(host).has("--autopilot"), "the sandbox-scene spelling stays on the scenes")


func test_a_scene_rung_is_untouched_by_all_of_this() -> void:
	var panel: PanelContainer = await _panel()
	panel.get_node("%AutopilotToggle").button_pressed = true

	var host: PackedStringArray = panel.build_args(NetworkTransport.Role.HOST, MP_SANDBOX)

	assert_true(Array(host).has(MP_SANDBOX))
	assert_true(Array(host).has("--role=host"))
	assert_true(Array(host).has("--autopilot"))
