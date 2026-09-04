extends GutTest

## #718 — the Command Tray's melee body must stay BOUNDED.
##
## A `Control`'s rect is clamped up to `get_combined_minimum_size()`, so the
## tray's anchors lose to its content's minimum size. Before this, a 45-node
## blade rendered 45 fifteen-pixel `CapacityPip`s in one `GridContainer` row,
## which gave `MeleeBody` an unbounded minimum width — the tray grew rightward
## and slid under the End Turn button. Re-anchoring the tray in `hud_root.tscn`
## leaves it ~930px, so **the body's minimum width must stay at or under 890.**
##
## That number is the whole point of this file. "It looked fine today" is not a
## property; a headless assertion on `get_combined_minimum_size().x` is, and it
## is the only thing that will catch the next widget added to the blade row.
##
## Two independent mechanisms hold the bound, and both are covered here:
##   - **collapsing** — a run of more than `collapse_threshold` identical pips
##     renders as one pip plus `× N` (owner call 2026-09-04: *"collapse, loses
##     interactivity -> fine, for that amount its unwieldy to be clicking
##     pips"*); and
##   - **`columns`** — the grid wraps, so even the pathological blade whose pips
##     alternate signature (and therefore collapses to nothing) cannot exceed
##     one row's worth of width. Collapsing alone would NOT bound that case,
##     which is why `test_an_uncollapsible_blade_is_still_bounded` exists.

const _MAX_TRAY_WIDTH := 890.0

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BLIPS_SCENE := preload("res://ui/gauges/capacity_blips.tscn")
const _MELEE_BODY := preload("res://ui/hud/command_tray/bodies/melee_body.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _battle: BattleSystem
var _tm: TurnManager
var _ctl: PlayerInputController
var _player: Entity
var _pivot: SkillNode
var _leaves: Array[SkillNode] = []


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_tm = autofree(TurnManager.new())
	add_child(_tm)

	_battle = autofree(BattleSystem.new())
	_battle.graph = _graph
	_battle.turn_manager = _tm
	add_child(_battle)

	_player = autofree(Entity.new())
	_player.display_name = "Player"
	_player.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(_player)

	_leaves = []


## A pivot with `leaf_count` leaves hanging off it, every one of them allocated
## to the player — so each is a legal blade pick straight off the pivot and the
## blade can be grown to any size in one pass.
func _build_star(leaf_count: int) -> void:
	_pivot = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_pivot.name = "Pivot"
	_graph.add_skill_node(_pivot)
	for i in leaf_count:
		var leaf := _SKILL_NODE_SCENE.instantiate() as SkillNode
		leaf.name = "Leaf%02d" % i
		_graph.add_skill_node(leaf)
		_graph.add_edge(_pivot, leaf)
		_leaves.append(leaf)
	await get_tree().process_frame

	# blade_size is an ordinary board scalar, so this is a plain base write —
	# the fixture entity's real default is 1, far too small to draw the row this
	# file is about.
	_player.stat_board.blade_size.base_value = float(leaf_count)
	_player.core_location = _pivot
	_alloc.force_allocate(_player, _pivot)
	for leaf in _leaves:
		_alloc.force_allocate(_player, leaf)

	_tm.start_turn(_player)
	_player.stat_board.action_points.restore_to_full()

	_ctl = PlayerInputController.new()
	_ctl.graph = _graph
	_ctl.allocation_system = _alloc
	_ctl.battle_system = _battle
	_ctl.turn_manager = _tm
	_ctl.player = _player
	add_child_autofree(_ctl)


## The body, bound and laid out, with `blade` leaves picked into the blade.
func _mount_body(blade: int) -> MeleeBody:
	_battle.request_attack_mode(BattleSystem.AttackMode.MELEE)
	var plan := _battle.attack_plan as MeleeAttackPlan
	assert_not_null(plan, "fixture check: melee must be the active plan")
	plan.attacker = _player
	plan._on_node_left_clicked(_pivot)
	for i in blade:
		plan._on_node_left_clicked(_leaves[i])
	assert_eq(plan.blade_nodes.size(), blade,
			"fixture check: every leaf click must land in the blade")

	var body := _MELEE_BODY.instantiate() as MeleeBody
	add_child_autofree(body)
	await get_tree().process_frame
	body.bind(_player, _battle, _ctl)
	await get_tree().process_frame
	return body


# ── The bound ────────────────────────────────────────────────────────────────

func test_a_full_45_node_blade_keeps_the_tray_body_under_890px() -> void:
	await _build_star(45)
	var body := await _mount_body(45)

	var w := body.get_combined_minimum_size().x
	var content := (body.get_node("BodyContent/Row") as Control).get_combined_minimum_size().x
	gut.p("45-node blade — MeleeBody min width %.1f px, its content row %.1f px"
			% [w, content])
	assert_lte(w, _MAX_TRAY_WIDTH,
			"the melee body's minimum width is what the tray's rect is clamped "
			+ "up to — over %d it slides under the End Turn button" % int(_MAX_TRAY_WIDTH))
	# The panel carries a 700px authored floor, so the assertion above alone
	# would keep passing right up until the content crossed 700 and then jump
	# straight past the real limit. Pin the CONTENT separately, at the same
	# budget minus the body's 16px margins, so the headroom is measured rather
	# than assumed.
	assert_lte(content, _MAX_TRAY_WIDTH - 32.0,
			"the blade row's own content is what actually grows with blade size")


func test_an_uncollapsible_blade_is_still_bounded() -> void:
	# The case collapsing alone does NOT cover: alternate the manual-upgrade
	# marker down the row so no two consecutive pips share a signature and every
	# run is length 1. `columns` is the thing holding the bound here.
	await _build_star(45)
	var body := await _mount_body(45)
	var blips: CapacityBlips = body.get_node("%BladeBlips")
	var markers: Array[bool] = []
	for i in 45:
		markers.append(i % 2 == 0)
	blips.manual_markers = markers
	await get_tree().process_frame

	var content := (body.get_node("BodyContent/Row") as Control).get_combined_minimum_size().x
	gut.p("uncollapsible 45-node blade — content row %.1f px" % content)
	assert_lte(body.get_combined_minimum_size().x, _MAX_TRAY_WIDTH,
			"a blade that cannot collapse at all must still be bounded — that is "
			+ "the grid's `columns`, not the collapse threshold")
	assert_lte(content, _MAX_TRAY_WIDTH - 32.0,
			"and bounded in its CONTENT, not just against the panel's 700px floor")


func test_a_half_grown_blade_is_bounded_too() -> void:
	# Two runs (filled reds, then empty greys), both over threshold.
	await _build_star(45)
	var body := await _mount_body(20)
	assert_lte(body.get_combined_minimum_size().x, _MAX_TRAY_WIDTH)
	assert_lte((body.get_node("BodyContent/Row") as Control)
			.get_combined_minimum_size().x, _MAX_TRAY_WIDTH - 32.0)


# ── Collapsing, on the widget itself ─────────────────────────────────────────

func _blips(max_count: int, threshold: int) -> CapacityBlips:
	var b := _BLIPS_SCENE.instantiate() as CapacityBlips
	b.collapse_threshold = threshold
	b.max_count = max_count
	b.count = max_count
	add_child_autofree(b)
	return b


func _pip_count(b: CapacityBlips) -> int:
	var n := 0
	for child in b.get_children():
		if child is CapacityPip:
			n += 1
	return n


func test_a_run_of_thirty_identical_pips_collapses_to_one_chip() -> void:
	var b := _blips(30, 15)
	assert_eq(_pip_count(b), 1, "30 identical pips must render as ONE chip")
	assert_eq(b.get_child_count(), 2, "chip + its `× N` label, nothing else")
	var label := b.get_child(1) as Label
	assert_not_null(label, "the second child is the run-count label")
	assert_true(label.text.contains("30"),
			"the label must name the run size — got %s" % label.text)


func test_a_run_at_the_threshold_is_left_alone() -> void:
	# Strictly LONGER than the threshold collapses; exactly the threshold does
	# not. The off-by-one matters: 15 clickable pips is the last size the owner
	# call says is still worth clicking.
	var at := _blips(15, 15)
	assert_eq(_pip_count(at), 15, "a run OF the threshold renders in full")
	assert_eq(at.get_child_count(), 15, "and grows no label")

	var over := _blips(16, 15)
	assert_eq(_pip_count(over), 1, "one more than the threshold collapses")


func test_two_runs_collapse_independently() -> void:
	var b := _blips(40, 15)
	b.count = 20
	await get_tree().process_frame
	assert_eq(_pip_count(b), 2, "filled run + empty run, one chip each")
	assert_eq(b.get_child_count(), 4, "two chips, two labels")


func test_a_style_break_splits_a_run() -> void:
	var b := _blips(40, 15)
	var markers: Array[bool] = []
	for i in 40:
		markers.append(i >= 20)
	b.manual_markers = markers
	await get_tree().process_frame
	assert_eq(_pip_count(b), 2,
			"the manual marker is part of the signature, so it breaks the run")


# ── The default every other consumer keeps ───────────────────────────────────

func test_threshold_zero_is_exactly_todays_behaviour() -> void:
	# CombatCardMelee's size gauge and the Magic spell-bar degree icon never set
	# a threshold, and must be untouched by any of this.
	var b := _blips(30, 0)
	assert_eq(b.get_child_count(), 30, "one child per pip, no labels")
	assert_eq(_pip_count(b), 30)
	for i in 30:
		assert_eq(b.get_child(i).name, StringName("CapacityPip_%02d" % i),
				"the flat path's pip names are unchanged")
	assert_eq(b.collapse_threshold, 0, "OFF is the shipped default")


func test_the_shipped_blips_scene_defaults_to_no_collapsing() -> void:
	var b := _BLIPS_SCENE.instantiate() as CapacityBlips
	add_child_autofree(b)
	assert_eq(b.collapse_threshold, 0,
			"a bare CapacityBlips must behave exactly as it did before #718")


# ── A collapsed chip hovers its whole run ────────────────────────────────────

func test_a_collapsed_chip_force_hovers_every_node_it_stands_for() -> void:
	await _build_star(45)
	var body := await _mount_body(45)
	var blips: CapacityBlips = body.get_node("%BladeBlips")
	assert_eq(_pip_count(blips), 1, "fixture check: the 45 picks are one chip")

	var chip := blips.get_child(0) as CapacityPip
	chip.mouse_entered.emit()
	for i in 45:
		assert_true(_leaves[i]._forced_hover,
				"leaf %d is inside the hovered run and must be lit" % i)

	# THE invariant: nothing is left forced-hovered after a clear, however many
	# pips were over a node. A rebuild frees the pip under the cursor without
	# ever firing its mouse_exited, so this is the only thing that balances.
	body._clear_hover()
	for i in 45:
		assert_false(_leaves[i]._forced_hover,
				"leaf %d must be released by _clear_hover()" % i)


func test_a_refresh_releases_every_forced_hover() -> void:
	await _build_star(45)
	var body := await _mount_body(45)
	var blips: CapacityBlips = body.get_node("%BladeBlips")
	(blips.get_child(0) as CapacityPip).mouse_entered.emit()
	assert_true(_leaves[0]._forced_hover, "fixture check: the run is hovered")

	body._refresh()
	for i in 45:
		assert_false(_leaves[i]._forced_hover,
				"leaf %d survived a _refresh() still forced-hovered" % i)


func test_a_collapsed_chip_is_click_dead() -> void:
	# Owner's accepted tradeoff — clicking the graph node still works.
	await _build_star(45)
	var body := await _mount_body(45)
	var blips: CapacityBlips = body.get_node("%BladeBlips")
	watch_signals(blips)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	(blips.get_child(0) as CapacityPip).gui_input.emit(click)
	assert_signal_emit_count(blips, "pip_clicked", 0,
			"a chip standing for 45 nodes has no single node to toggle")


# ── The Ruler is gone ────────────────────────────────────────────────────────

func test_the_spend_pips_live_on_their_own_row_with_no_orphan_divider() -> void:
	await _build_star(3)
	var body := await _mount_body(3)
	assert_null(body.find_child("Ruler", true, false),
			"the row break IS the separator now — an orphan divider reads as a bug")
	var spent: CapacityBlips = body.get_node("%UpgradeBlips")
	var blade: CapacityBlips = body.get_node("%BladeBlips")
	assert_ne(spent.get_parent(), blade.get_parent(),
			"blade pips and spend pips must be on separate rows")
	assert_eq(spent.get_parent().name, StringName("SpentRow"))


# ── Z / X arm the temp-upgrade cards, by catalog INDEX ───────────────────────

func _press(action: StringName) -> void:
	var ev := InputEventKey.new()
	var mapped: Array[InputEvent] = InputMap.action_get_events(action)
	assert_gt(mapped.size(), 0, "no event mapped for %s" % action)
	ev.physical_keycode = (mapped[0] as InputEventKey).physical_keycode
	ev.pressed = true
	_ctl._unhandled_key_input(ev)


func test_z_and_x_arm_the_first_two_catalog_entries() -> void:
	await _build_star(3)
	await _mount_body(2)

	_press(&"ui_temp_upgrade_1")
	assert_eq(_ctl.temp_upgrade_arm(), MeleeAttackPlan.TEMP_UPGRADE_CATALOG[0],
			"Z arms catalog slot 0 — by INDEX, never by name")

	_press(&"ui_temp_upgrade_2")
	assert_eq(_ctl.temp_upgrade_arm(), MeleeAttackPlan.TEMP_UPGRADE_CATALOG[1],
			"X arms catalog slot 1")


func test_re_pressing_the_same_key_cancels_the_arm() -> void:
	# Same toggle semantics the card click already has — one door, not two.
	await _build_star(3)
	await _mount_body(2)
	_press(&"ui_temp_upgrade_1")
	_press(&"ui_temp_upgrade_1")
	assert_null(_ctl.temp_upgrade_arm(), "re-press cancels")


func test_the_keys_are_dead_outside_melee() -> void:
	await _build_star(3)
	await _mount_body(2)
	_battle.request_attack_mode(BattleSystem.AttackMode.RANGED)
	assert_eq(_battle.attack_mode, BattleSystem.AttackMode.RANGED,
			"fixture check: melee must actually be gone")

	_press(&"ui_temp_upgrade_1")
	assert_null(_ctl.temp_upgrade_arm(),
			"the cards only exist in the melee tray, so the keys are modal too")


func test_the_keys_are_dead_when_the_player_cannot_act() -> void:
	await _build_star(3)
	await _mount_body(2)
	# Handed straight to the field rather than through end_turn(), which ticks
	# on to whoever is ready next — with a one-entity fixture that is the player
	# again, and the gate never closes.
	_tm.current_entity = null
	assert_false(_ctl.can_player_act(), "fixture check: it is not the player's turn")

	_press(&"ui_temp_upgrade_1")
	assert_null(_ctl.temp_upgrade_arm())


func test_an_index_past_the_catalog_is_a_silent_no_op() -> void:
	# The binding is positional, so growing the keycap list ahead of the catalog
	# (or shrinking the catalog) must not crash — it just does nothing.
	await _build_star(3)
	await _mount_body(2)
	assert_false(_ctl._arm_temp_upgrade_at(MeleeAttackPlan.TEMP_UPGRADE_CATALOG.size()),
			"an out-of-range slot is unconsumed, leaving the key free downstream")
	assert_null(_ctl.temp_upgrade_arm())


func test_the_cards_print_the_key_that_arms_them() -> void:
	# The character comes from PlayerInputController, not a literal in the card
	# scene — so a third catalog entry gets its keycap by adding ONE entry there.
	await _build_star(3)
	var body := await _mount_body(2)
	var row: HBoxContainer = body.get_node("%UpgradeRow")
	assert_eq(row.get_child_count(), MeleeAttackPlan.TEMP_UPGRADE_CATALOG.size(),
			"one card per catalog entry")
	for i in row.get_child_count():
		var card := row.get_child(i) as TempUpgradeButton
		var cap := PlayerInputController.temp_upgrade_keycap(i)
		assert_eq(card.keycap, cap, "card %d must print its own bound key" % i)
		assert_true((card.get_node("%Title") as Label).text.ends_with("(%s)" % cap),
				"the keycap rides the title the way Reform's does — got %s"
				% (card.get_node("%Title") as Label).text)


func test_a_catalog_slot_with_no_key_prints_no_keycap() -> void:
	assert_eq(PlayerInputController.temp_upgrade_keycap(99), "",
			"an unbound slot shows nothing rather than a wrong key")
	assert_eq(PlayerInputController.temp_upgrade_keycap(-1), "")


func test_every_bound_hotkey_actually_exists_in_the_input_map() -> void:
	for action in PlayerInputController.TEMP_UPGRADE_HOTKEYS:
		assert_true(InputMap.has_action(action),
				"%s is bound in code but missing from project.godot" % action)
	assert_eq(PlayerInputController.TEMP_UPGRADE_HOTKEYS.size(),
			PlayerInputController.TEMP_UPGRADE_KEYCAPS.size(),
			"the actions and their printed keycaps are parallel lists")


func test_the_hotkeys_do_not_steal_the_debug_clipboard_key() -> void:
	# `c` belongs to DebugClipboard. Z and X were the owner's pick precisely to
	# leave it alone.
	for action in PlayerInputController.TEMP_UPGRADE_HOTKEYS:
		for ev in InputMap.action_get_events(action):
			assert_ne((ev as InputEventKey).physical_keycode, KEY_C,
					"%s must not take C from DebugClipboard" % action)
