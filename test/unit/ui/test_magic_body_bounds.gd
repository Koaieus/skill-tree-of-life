extends GutTest

## #753 — the Magic tray body must be bounded by CONSTRUCTION, not by luck.
##
## A [Control]'s rect is clamped UP to [method Control.get_combined_minimum_size],
## so anchors lose to content min size. The spell bar used to be an
## [HBoxContainer] of fixed 96px buttons, one per spell, and [SpellBook] grows
## through loot without bound — so the body's min width grew past the tray's
## slot and pushed the whole Command Tray out from under the End Turn button.
## "Looked fine at 1440 with 8 spells" is exactly the check that did not catch
## it; the assertion that does is a 20-spell book against a fixed budget.
##
## Budget: the tray slot is ~930px wide (hud_root.tscn anchors it to
## `offset_right = -152`), and the body is authored ~180px tall and may grow a
## little upward over the graph when a second row of spells appears.
const MAX_BODY_MIN_WIDTH: float = 890.0
const MAX_BODY_MIN_HEIGHT: float = 230.0

## Width the tray actually hands the body. Layout-dependent behaviour (does the
## book fit one row?) is meaningless at the default zero width, so every test
## here forces a realistic rect and lets a frame settle.
const TRAY_WIDTH: float = 930.0

const _MAGIC_BODY_SCENE := preload("res://ui/hud/command_tray/bodies/magic_body.tscn")

var _body: MagicBody
var _bar: SpellPickerBar


func before_each() -> void:
	_body = _MAGIC_BODY_SCENE.instantiate() as MagicBody
	add_child_autofree(_body)
	_bar = _body.get_node("%SpellPickerBar") as SpellPickerBar


## Deliberately synthetic spells: the shipped catalog's costs are owner tuning,
## and what is under test is COUNT, not content.
func _book(count: int) -> SpellBook:
	var book := SpellBook.new()
	for i in count:
		var spell := SpellDef.new()
		spell.name = "Spell %d" % i
		spell.mana_cost = 0
		spell.min_degree = 0
		book.learn(spell)
	return book


## Bind the book, give the body the tray's real width, and let the container
## sort + the bar's resize-driven relayout settle.
func _settle(count: int) -> void:
	_bar.bind_spellbook(_book(count))
	_body.size = Vector2(TRAY_WIDTH, _body.get_combined_minimum_size().y)
	await get_tree().process_frame
	await get_tree().process_frame
	_body.size = Vector2(TRAY_WIDTH, _body.get_combined_minimum_size().y)
	await get_tree().process_frame


func test_a_twenty_spell_book_never_widens_or_heightens_the_tray() -> void:
	await _settle(20)
	var min_size := _body.get_combined_minimum_size()
	gut.p("20-spell magic body min size = %s" % min_size)
	assert_lt(min_size.x, MAX_BODY_MIN_WIDTH + 1.0, "min width must stay inside the tray slot")
	assert_lt(min_size.y, MAX_BODY_MIN_HEIGHT + 1.0, "min height must stay inside the tray budget")


## The whole point of the flow container: min width is ONE button, so it is the
## SAME whether the book holds 2 spells or 20. If this ever diverges, some
## consumer has re-introduced a per-spell contribution to the min width.
func test_min_width_is_independent_of_spell_count() -> void:
	await _settle(2)
	var small := _body.get_combined_minimum_size().x
	await _settle(20)
	var large := _body.get_combined_minimum_size().x
	gut.p("min width: 2 spells = %f, 20 spells = %f" % [small, large])
	assert_almost_eq(large, small, 0.5, "spell count must not move the body's min width")


func test_a_small_book_stays_one_row_at_full_size() -> void:
	await _settle(2)
	assert_eq(_bar.get_row_count(), 1, "2 spells fit one row")
	assert_almost_eq(_bar.get_button_px(), SpellPickerBar.FULL_BUTTON_PX, 0.5, "no wrap means full-size buttons")


func test_a_big_book_wraps_to_compact_buttons() -> void:
	await _settle(20)
	assert_gt(_bar.get_row_count(), 1, "20 spells cannot fit one row")
	assert_almost_eq(_bar.get_button_px(), SpellPickerBar.COMPACT_BUTTON_PX, 0.5, "wrapping shrinks the buttons")


## Rows past the cap scroll instead of growing the body, so the scroll viewport
## is the same height at 20 spells as at 4.
func test_rows_past_the_cap_scroll_instead_of_growing() -> void:
	var scroll := _body.get_node("%SpellScroll") as ScrollContainer
	await _settle(20)
	var tall := scroll.custom_minimum_size.y
	var capped := MagicBody.MAX_VISIBLE_ROWS * SpellPickerBar.COMPACT_BUTTON_PX \
		+ (MagicBody.MAX_VISIBLE_ROWS - 1) * SpellPickerBar.V_SEPARATION
	assert_almost_eq(tall, capped, 0.5, "viewport caps at MAX_VISIBLE_ROWS rows")
	assert_true(_bar.get_combined_minimum_size().y > tall, "the bar itself is taller than the viewport, i.e. it scrolls")


## The container swap must not have cost the bar any of its behaviour: one
## shared ButtonGroup with allow_unpress = false, and sync_selected still
## finding its button.
func test_selection_survives_the_container_swap() -> void:
	await _settle(5)
	var buttons: Array[SpellPickerButton] = []
	for child in _bar.get_children():
		if child is SpellPickerButton and not child.is_queued_for_deletion():
			buttons.append(child as SpellPickerButton)
	assert_eq(buttons.size(), 5, "one button per spell")
	var group := buttons[0].button_group
	assert_not_null(group, "buttons keep a ButtonGroup")
	assert_false(group.allow_unpress, "radio semantics survive")
	for btn in buttons:
		assert_eq(btn.button_group, group, "all buttons share one group")
		# No gating attacker was ever set here, so `eligible_sources` is empty
		# and every button sits at toggle_mode = false (#728's steal guard) —
		# where `set_pressed_no_signal` is a no-op. Open the two clickable gates
		# by hand; the act gate and the group are what this test is about.
		btn.set_affordable(true)
		btn.set_has_caster(true)
	_bar.sync_selected(buttons[3].spell)
	assert_true(buttons[3].button_pressed, "sync_selected marks its button")
	assert_false(buttons[0].button_pressed, "and unmarks the others")
