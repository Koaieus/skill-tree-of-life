extends GutTest

var _catalog: TempUpgradeCatalog = preload("res://attack/melee/temp_upgrade_catalog.tres")

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

const _BLIPS_SCENE := preload("res://ui/gauges/capacity_blips.tscn")
const _MELEE_BODY := preload("res://ui/hud/command_tray/bodies/melee_body.tscn")

var _world: TestWorld
var _graph: Graph
var _alloc: AllocationSystem
var _battle: BattleSystem
var _tm: TurnManager
var _ctl: PlayerInputController
var _player: Entity
var _pivot: SkillNode
var _leaves: Array[SkillNode] = []


func before_each() -> void:
	_world = TestWorld.create(self)
	_graph = _world.graph
	_alloc = _world.allocator()

	_tm = autofree(TurnManager.new())
	add_child(_tm)

	_battle = autofree(BattleSystem.new())
	_battle.temp_upgrade_catalog = _catalog
	_battle.graph = _graph
	_battle.turn_manager = _tm
	add_child(_battle)

	_player = _world.add_entity("Player")

	_leaves = []


## A pivot with `leaf_count` leaves hanging off it, every one of them allocated
## to the player — so each is a legal blade pick straight off the pivot and the
## blade can be grown to any size in one pass.
func _build_star(leaf_count: int) -> void:
	_pivot = _world.add_node(&"Pivot")
	for i in leaf_count:
		var leaf := _world.add_node(StringName("Leaf%02d" % i))
		_world.link(_pivot, leaf)
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
	_ctl.arm_attack(BattleSystem.AttackMode.MELEE)
	var plan := _ctl.armed_stack.attack_plan() as MeleeAttackPlan
	assert_not_null(plan, "fixture check: melee must be the active plan")
	plan.attacker = _player
	_ctl.route_left_click(_pivot)
	for i in blade:
		_ctl.route_left_click(_leaves[i])
	assert_eq(plan.blade_nodes.size(), blade,
			"fixture check: every leaf click must land in the blade")

	var body := _MELEE_BODY.instantiate() as MeleeBody
	add_child_autofree(body)
	await get_tree().process_frame
	body.bind(_player, _battle, _ctl)
	await get_tree().process_frame
	return body


# ── The bound ────────────────────────────────────────────────────────────────

## A catalog of [constant _FIXTURE_KINDS] aspect-free placeable kinds, written
## once per run to `user://` and scanned through a fresh [TempUpgradeCatalog]
## (its [method TempUpgradeCatalog.kinds] caches, so [member folder] is set
## before the first read).
const _FIXTURE_DIR := "user://test_melee_body_width_addons"
const _FIXTURE_KINDS := 10


func _fixture_catalog() -> TempUpgradeCatalog:
	DirAccess.make_dir_recursive_absolute(_FIXTURE_DIR)
	for i in _FIXTURE_KINDS:
		var path := _FIXTURE_DIR.path_join("fixture_%02d_addon.tscn" % i)
		if not FileAccess.file_exists(path):
			var addon := SkillNodeAddon.new()
			addon.name = "Fixture%02d" % i
			addon.temp_placeable = true
			var packed := PackedScene.new()
			packed.pack(addon)
			addon.free()
			ResourceSaver.save(packed, path)
	var catalog := TempUpgradeCatalog.new()
	catalog.folder = _FIXTURE_DIR
	assert_eq(catalog.offered().size(), _FIXTURE_KINDS,
			"fixture check: every generated kind is scanned and placeable")
	return catalog


func test_a_catalog_of_ten_kinds_keeps_the_tray_body_bounded() -> void:
	# The quickbar is a fixed row of hotkey-count slots, so the tray no longer
	# grows with the catalog.
	_battle.temp_upgrade_catalog = _fixture_catalog()
	await _build_star(3)
	var body := await _mount_body(2)
	var w := body.get_combined_minimum_size().x
	gut.p("%d-kind catalog — MeleeBody min width %.1f px" % [_FIXTURE_KINDS, w])
	assert_lte(w, _MAX_TRAY_WIDTH,
			"a catalog-sized card row slides the tray under the End Turn button")



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


# ── Z–B arm the quickbar's favourites, by SLOT ───────────────────────────────

func _press(action: StringName) -> void:
	var ev := InputEventKey.new()
	var mapped: Array[InputEvent] = InputMap.action_get_events(action)
	assert_gt(mapped.size(), 0, "no event mapped for %s" % action)
	ev.physical_keycode = (mapped[0] as InputEventKey).physical_keycode
	ev.pressed = true
	_ctl._unhandled_key_input(ev)


func _slots() -> Array[PackedScene]:
	return _ctl.temp_quickbar().slots


func test_z_and_x_arm_the_first_two_quickbar_slots() -> void:
	await _build_star(3)
	await _mount_body(2)
	assert_not_null(_slots()[0], "fixture check: the first melee plan autofilled slot 1")
	assert_not_null(_slots()[1], "fixture check: ...and slot 2")

	_press(&"ui_temp_upgrade_1")
	assert_eq(_ctl.temp_upgrade_arm(), _slots()[0],
			"Z arms quickbar slot 1 — by SLOT, never by name")

	_press(&"ui_temp_upgrade_2")
	assert_eq(_ctl.temp_upgrade_arm(), _slots()[1],
			"X arms quickbar slot 2")


func test_the_first_melee_plan_autofills_with_what_the_player_can_place() -> void:
	await _build_star(3)
	await _mount_body(2)
	var available := _ctl.available_temp_kinds()
	for i in _slots().size():
		assert_eq(_slots()[i], available[i] if i < available.size() else null,
				"slot %d holds the %d-th placeable kind, in catalog order" % [i, i])
	for scene in available:
		for id in SkillNodeAddon.temp_costs_of(scene):
			if id != &"blade_size":
				assert_gt(AspectCurrency.cap_of(_player, id), 0,
						"a kind costing an aspect held at 0 is not placeable")


func test_a_right_click_swap_puts_the_pick_in_that_slot_and_pins_it() -> void:
	await _build_star(3)
	var body := await _mount_body(2)
	var row: HBoxContainer = body.get_node("%Quickbar")
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	(row.get_child(3) as Control).gui_input.emit(right)
	var fan := body.get_node("%SwapFan") as CardFan
	assert_true(fan.visible, "right-click on a slot opens the swap picker")
	assert_eq(body.swap_slot(), 3)
	assert_eq(fan.cards().size(), _ctl.available_temp_kinds().size(),
			"the picker lists every kind the player can place")

	var pick := _slots()[0]
	fan.picked.emit(pick)
	assert_false(fan.visible, "a pick closes the picker")
	assert_eq(_slots()[3], pick, "the picked scene lands in the right-clicked slot")
	assert_true(_ctl.temp_quickbar().pinned[3], "a manual swap pins its slot")
	assert_null(_slots()[0], "the kind moved rather than doubling")
	await get_tree().process_frame
	assert_true(row.get_child(3) is TempUpgradeButton, "the row repainted the swapped slot")
	_press(&"ui_temp_upgrade_4")
	assert_eq(_ctl.temp_upgrade_arm(), pick, "its key arms the swapped-in kind")


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
	_ctl.arm_attack(BattleSystem.AttackMode.RANGED)
	assert_eq(_attack_mode(), BattleSystem.AttackMode.RANGED,
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
	_tm.adopt_turn(null, _tm.turns_taken)
	assert_false(_ctl.can_player_act(), "fixture check: it is not the player's turn")

	_press(&"ui_temp_upgrade_1")
	assert_null(_ctl.temp_upgrade_arm())


func test_an_empty_slot_is_a_silent_no_op() -> void:
	# The binding is positional, so an empty slot (or one past the bar) must not
	# crash — it just does nothing.
	await _build_star(3)
	await _mount_body(2)
	_ctl.temp_quickbar().swap(0, null)
	assert_null(_slots()[0], "fixture check: slot 1 is empty")
	assert_false(_ctl._arm_temp_upgrade_at(0),
			"an empty slot is unconsumed, leaving the key free downstream")
	assert_false(_ctl._arm_temp_upgrade_at(_slots().size()), "so is one past the bar")
	assert_null(_ctl.temp_upgrade_arm())


func test_the_cards_print_the_key_that_arms_them() -> void:
	# The character comes from PlayerInputController, not a literal in the card
	# scene — so a sixth slot gets its keycap by adding ONE entry there.
	await _build_star(3)
	var body := await _mount_body(2)
	var row: HBoxContainer = body.get_node("%Quickbar")
	assert_eq(row.get_child_count(), PlayerInputController.TEMP_UPGRADE_HOTKEYS.size(),
			"one slot per arming key, whatever the catalog holds")
	for i in row.get_child_count():
		var card := row.get_child(i) as TempUpgradeButton
		assert_eq(card != null, _slots()[i] != null,
				"slot %d is a card iff it holds a favourite" % i)
		if card == null:
			continue
		var cap := PlayerInputController.temp_upgrade_keycap(i)
		assert_eq(card.keycap, cap, "card %d must print its own bound key" % i)
		# The glyph moved out of the title and into the shared corner KeyChip
		# (owner call 2026-09-04: one keycap grammar across tabs, spell tiles
		# and cards), so the title is now the bare name.
		var chip := card.get_node("%KeyChip") as KeyChip
		assert_eq(chip.text, cap, "card %d's chip must print its own bound key" % i)
		assert_true(chip.visible, "a bound card shows its chip")
		assert_false((card.get_node("%Title") as Label).text.contains("("),
				"the keycap is no longer a title suffix — got %s"
				% (card.get_node("%Title") as Label).text)


func test_a_catalog_slot_with_no_key_prints_no_keycap() -> void:
	assert_eq(PlayerInputController.temp_upgrade_keycap(99), "",
			"an unbound slot shows nothing rather than a wrong key")
	assert_eq(PlayerInputController.temp_upgrade_keycap(-1), "")


func test_every_bound_hotkey_actually_exists_in_the_input_map() -> void:
	for action in PlayerInputController.TEMP_UPGRADE_HOTKEYS:
		assert_true(InputMap.has_action(action),
				"%s is bound in code but missing from project.godot" % action)
		assert_ne(KeyChip.keycap_for(action), "",
				"%s must carry a key event, or its card prints no keycap" % action)


func test_the_keycap_follows_a_rebind_of_the_action() -> void:
	# The cap is DERIVED from the InputMap, never a hand-typed parallel list.
	# InputMap is process-global (shards share a process) — restore it.
	var action := PlayerInputController.TEMP_UPGRADE_HOTKEYS[0]
	var saved := InputMap.action_get_events(action).duplicate()
	InputMap.action_erase_events(action)
	var q := InputEventKey.new()
	q.physical_keycode = KEY_Q
	InputMap.action_add_event(action, q)
	var cap := PlayerInputController.temp_upgrade_keycap(0)
	InputMap.action_erase_events(action)
	for ev in saved:
		InputMap.action_add_event(action, ev)
	assert_eq(cap, "Q", "rebinding the action must move the printed keycap with it")
	assert_eq(PlayerInputController.temp_upgrade_keycap(0), "Z", "restored")


func test_the_hotkeys_do_not_steal_the_debug_clipboard_key() -> void:
	# `c` belongs to DebugClipboard. Z and X were the owner's pick precisely to
	# leave it alone.
	for action in PlayerInputController.TEMP_UPGRADE_HOTKEYS:
		for ev in InputMap.action_get_events(action):
			assert_ne((ev as InputEventKey).physical_keycode, KEY_C,
					"%s must not take C from DebugClipboard" % action)


## The armed attack level's mode, NONE with no attack level on the branch.
func _attack_mode() -> BattleSystem.AttackMode:
	var level := _ctl.armed_stack.find(AttackArmMode) as AttackArmMode
	return level.mode if level != null else BattleSystem.AttackMode.NONE


func test_an_aspect_gained_from_zero_fills_the_next_open_slot_with_its_kinds() -> void:
	await _build_star(3)
	await _mount_body(2)
	var aspect := &""
	var costed: PackedScene = null
	for scene in _catalog.offered():
		for id in SkillNodeAddon.temp_costs_of(scene):
			if id != &"blade_size" and AspectCurrency.cap_of(_player, id) == 0 \
					and _player.stat_board.get_stat(id) != null:
				aspect = id
				costed = scene
	assert_ne(aspect, &"", "fixture check: some offered kind costs an aspect held at 0")
	assert_false(_slots().has(costed), "fixture check: it is not on the bar yet")
	var before := _slots().duplicate()
	assert_true(before.has(null), "fixture check: the bar has an open slot")

	_player.stat_board.get_stat(aspect).base_value = 1.0
	assert_true(_slots().has(costed), "0 → 1 of %s puts its kind on the bar" % aspect)
	for i in before.size():
		if before[i] != null:
			assert_eq(_slots()[i], before[i], "slot %d was filled, so it is untouched" % i)
