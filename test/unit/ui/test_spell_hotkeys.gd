extends GutTest

## Number keys pick spells, and every keycap on screen comes from the binding.
##
## Owner calls (2026-09-04):
##   * *"spells best be indexed by number key! (regular row OR keypad)"* — so
##     each `ui_select_spell_N` carries BOTH events, and that is asserted here
##     rather than eyeballed in `project.godot`.
##   * *"maybe change `1` hotkey for Management to be backtick instead? or tab?
##     tab puts the primary ones on a row"* — **Tab**, which is what freed the
##     digits in the first place. Pinned below so a revert to `1` goes red on
##     the collision instead of silently stealing spell 1.
##   * Magic-tab-only, exactly as Z/X are melee-only: a stray digit must not
##     yank you out of the tab you are in.
##
## The keycap half matters as much as the binding half: a rebind that left a
## stale glyph painted would teach the player a key that does nothing.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _KEY_CHIP := preload("res://ui/common/key_chip.tscn")
const _SPELL_PICKER_BUTTON := preload("res://ui/spell_picker_bar/spell_picker_button.tscn")

var _graph: Graph
var _battle: BattleSystem
var _tm: TurnManager
var _ctl: PlayerInputController
var _player: Entity


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

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
	_tm.start_turn(_player)
	_player.stat_board.action_points.restore_to_full()

	_ctl = PlayerInputController.new()
	_ctl.graph = _graph
	_ctl.battle_system = _battle
	_ctl.turn_manager = _tm
	_ctl.player = _player
	add_child_autofree(_ctl)


## Deliberately synthetic: what is under test is POSITION, not content, and the
## shipped catalog's ordering is owner tuning.
func _stock_book(count: int) -> Array[SpellDef]:
	var book := _player.get_spellbook()
	var made: Array[SpellDef] = []
	for i in count:
		var spell := SpellDef.new()
		spell.name = "Spell %d" % i
		spell.mana_cost = 0
		spell.min_degree = 0
		book.learn(spell)
		made.append(spell)
	return made


## Feeds the FIRST event mapped to `action` (the top-row digit) unless
## `event_index` asks for the keypad twin.
func _press(action: StringName, event_index: int = 0) -> void:
	var mapped: Array[InputEvent] = InputMap.action_get_events(action)
	assert_gt(mapped.size(), event_index, "no event #%d mapped for %s" % [event_index, action])
	var ev := InputEventKey.new()
	ev.physical_keycode = (mapped[event_index] as InputEventKey).physical_keycode
	ev.pressed = true
	_ctl._unhandled_key_input(ev)


# ── The bindings exist and carry both rows ───────────────────────────────────

func test_every_spell_hotkey_is_bound_to_both_a_digit_and_its_keypad_twin() -> void:
	var digits := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
	var kp := [KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5, KEY_KP_6,
			KEY_KP_7, KEY_KP_8, KEY_KP_9]
	assert_eq(PlayerInputController.SPELL_HOTKEYS.size(), 9,
			"nine non-zero digits, nine actions")
	for i in PlayerInputController.SPELL_HOTKEYS.size():
		var action: StringName = PlayerInputController.SPELL_HOTKEYS[i]
		assert_true(InputMap.has_action(action),
				"%s is bound in code but missing from project.godot" % action)
		var codes: Array[int] = []
		for ev in InputMap.action_get_events(action):
			codes.append((ev as InputEventKey).physical_keycode)
		assert_true(digits[i] in codes, "%s must answer the top-row digit" % action)
		assert_true(kp[i] in codes, "%s must answer the keypad digit too" % action)


func test_manage_is_tab_and_no_longer_steals_a_digit() -> void:
	var codes: Array[int] = []
	for ev in InputMap.action_get_events(&"ui_select_manage_mode"):
		codes.append((ev as InputEventKey).physical_keycode)
	assert_true(KEY_TAB in codes, "Tab/Q/W/E is one physical row — owner call")
	assert_false(KEY_1 in codes, "`1` belongs to spell 1 now; two claims is a collision")


func test_tab_is_not_the_more_info_key() -> void:
	# The owner's own caveat on picking Tab. `ui_more_info` is Shift.
	for ev in InputMap.action_get_events(&"ui_more_info"):
		assert_ne((ev as InputEventKey).physical_keycode, KEY_TAB,
				"Tab must be genuinely free before the Manage tab takes it")


# ── Pressing a digit in MAGIC ────────────────────────────────────────────────

func test_a_digit_selects_the_spell_at_that_position() -> void:
	var spells := _stock_book(4)
	_battle.request_attack_mode(BattleSystem.AttackMode.MAGIC)
	_press(&"ui_select_spell_3")
	assert_eq(_battle.selected_spell, spells[2], "the 3 key picks the THIRD spell")
	_press(&"ui_select_spell_1")
	assert_eq(_battle.selected_spell, spells[0], "and 1 picks the first")


func test_the_keypad_digit_does_the_same_thing() -> void:
	var spells := _stock_book(4)
	_battle.request_attack_mode(BattleSystem.AttackMode.MAGIC)
	_press(&"ui_select_spell_2", 1)
	assert_eq(_battle.selected_spell, spells[1],
			"KP 2 and 2 are one binding, not two that can drift")


func test_a_digit_past_the_book_is_a_silent_no_op() -> void:
	_stock_book(2)
	_battle.request_attack_mode(BattleSystem.AttackMode.MAGIC)
	assert_false(_ctl._select_spell_at(7),
			"unconsumed, so the key stays free for whatever wants it downstream")
	assert_null(_battle.selected_spell)


func test_the_digits_are_dead_outside_magic() -> void:
	_stock_book(4)
	_battle.request_attack_mode(BattleSystem.AttackMode.MELEE)
	assert_eq(_battle.attack_mode, BattleSystem.AttackMode.MELEE,
			"fixture check: magic must actually be gone")
	_press(&"ui_select_spell_1")
	assert_null(_battle.selected_spell,
			"a stray digit must not reach across from the tab you are in")
	assert_false(_ctl._select_spell_at(0), "and it must not consume the key either")


func test_the_digits_are_dead_when_the_player_cannot_act() -> void:
	_stock_book(4)
	_battle.request_attack_mode(BattleSystem.AttackMode.MAGIC)
	_tm.current_entity = null
	assert_false(_ctl.can_player_act(), "fixture check: it is not the player's turn")
	_press(&"ui_select_spell_1")
	assert_null(_battle.selected_spell)


func test_a_null_hole_in_the_book_does_not_shift_the_digits() -> void:
	# The bar skips nulls when it builds tiles, so the controller must count the
	# same way — otherwise the glyph painted on a tile picks its neighbour.
	var spells := _stock_book(3)
	var book := _player.get_spellbook()
	book.spells.insert(1, null)
	assert_eq(PlayerInputController.spell_at_slot(book, 1), spells[1],
			"slot 1 is the second REAL spell, not the hole")


# ── The keycap is derived from the binding, never authored ───────────────────

func test_the_keycap_is_the_index_and_runs_out_after_nine() -> void:
	assert_eq(PlayerInputController.spell_keycap(0), "1")
	assert_eq(PlayerInputController.spell_keycap(8), "9")
	assert_eq(PlayerInputController.spell_keycap(9), "",
			"a tenth spell is mouse-only — no chip beats a wrong chip")
	assert_eq(PlayerInputController.spell_keycap(-1), "")


func test_the_bar_numbers_its_tiles_in_book_order() -> void:
	var bar := SpellPickerBar.new()
	add_child_autofree(bar)
	var spells := _stock_book(11)
	bar.bind_spellbook(_player.get_spellbook())
	await get_tree().process_frame
	var tiles: Array[SpellPickerButton] = []
	for child in bar.get_children():
		if child is SpellPickerButton and not child.is_queued_for_deletion():
			tiles.append(child as SpellPickerButton)
	assert_eq(tiles.size(), spells.size(), "one tile per spell")
	for i in tiles.size():
		assert_eq(tiles[i].key_hint, PlayerInputController.spell_keycap(i),
				"tile %d prints the key that actually picks it" % i)
	assert_eq(tiles[9].key_hint, "", "the tenth tile carries no chip")
	assert_false((tiles[9].get_node("%KeyChip") as KeyChip).visible,
			"and hides the chip outright rather than showing an empty box")


func test_a_spell_tile_chip_does_not_grow_the_tile() -> void:
	# The chip is anchored (layout_mode = 1), so it is positioned and never
	# measured — which is what keeps MagicBody inside its min-size budget.
	var tile: SpellPickerButton = _SPELL_PICKER_BUTTON.instantiate()
	add_child_autofree(tile)
	await get_tree().process_frame
	var bare := tile.get_combined_minimum_size()
	tile.key_hint = "9"
	await get_tree().process_frame
	assert_eq(tile.get_combined_minimum_size(), bare,
			"a keycap must not be able to widen a 96px tile")


# ── One chip scene, three consumers, no shared stylebox ──────────────────────

func test_two_chips_do_not_share_one_stylebox() -> void:
	# `.claude/rules/godot-scene-authoring.md`: an inline SubResource is loaded
	# ONCE and reused by every instantiate(). The chip mutates border_color per
	# instance, so without `resource_local_to_scene` the last chip painted would
	# recolour every other chip on screen — silently, with no error.
	var a: KeyChip = _KEY_CHIP.instantiate()
	var b: KeyChip = _KEY_CHIP.instantiate()
	add_child_autofree(a)
	add_child_autofree(b)
	a.accent = Color.RED
	b.accent = Color.GREEN
	var sb_a := a.get_theme_stylebox(&"panel") as StyleBoxFlat
	var sb_b := b.get_theme_stylebox(&"panel") as StyleBoxFlat
	assert_ne(sb_a, sb_b, "each chip needs its OWN StyleBoxFlat")
	assert_eq(sb_a.border_color, Color.RED)
	assert_eq(sb_b.border_color, Color.GREEN, "the second chip must not have won both")


func test_the_chip_carries_its_size_as_a_property() -> void:
	# Owner: "legible enough yet not too big compared to the button they sit
	# on". Three consumers at three scales, one scene — so the size has to be a
	# knob, not three hand-tuned copies.
	var small: KeyChip = _KEY_CHIP.instantiate()
	add_child_autofree(small)
	small.text = "9"
	small.font_size = KeyChip.COMPACT_FONT_SIZE
	small.h_padding = 3
	await get_tree().process_frame
	var big: KeyChip = _KEY_CHIP.instantiate()
	add_child_autofree(big)
	big.text = "9"
	await get_tree().process_frame
	assert_lt(small.get_combined_minimum_size().y, big.get_combined_minimum_size().y,
			"the compact chip must actually be smaller than the tab-sized one")


func test_the_mode_tabs_print_their_own_bound_keys() -> void:
	var bar: AttackModeBar = preload("res://ui/attack_mode_bar/attack_mode_bar.tscn").instantiate()
	add_child_autofree(bar)
	await get_tree().process_frame
	var expected := {
		"ManageToggleButton": "Tab", "MeleeToggleButton": "Q",
		"RangedToggleButton": "W", "MagicToggleButton": "E",
	}
	for node_name: String in expected:
		var btn := bar.get_node(node_name) as AttackModeButton
		assert_eq(btn.key_hint, expected[node_name],
				"%s must print the key its shortcut actually uses" % node_name)
		assert_eq((btn.get_node("%KeyChip") as KeyChip).text, expected[node_name],
				"%s's chip must agree with its key_hint" % node_name)
