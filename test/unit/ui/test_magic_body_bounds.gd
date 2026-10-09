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
var _panel: Control


func before_each() -> void:
	_body = _MAGIC_BODY_SCENE.instantiate() as MagicBody
	add_child_autofree(_body)
	_bar = _body.get_node("%SpellPickerBar") as SpellPickerBar
	_panel = _body.get_node("%PickerPanel") as Control


## Deliberately synthetic spells: the shipped catalog's costs are owner tuning,
## and what is under test is COUNT, not content.
func _book(count: int) -> SpellBook:
	var book := SpellBook.new()
	for i in count:
		var spell := SpellDef.new()
		spell.name = "Spell %d" % i
		spell.min_degree = 0
		book.learn(spell)
	return book


## Bind the book, give the body the tray's real width, and let the container
## sort + the bar's resize-driven relayout settle. The bar lives in the floating
## %PickerPanel (#1485), shown here by hand: a hidden container never sorts, so
## the bar would sit at zero width. The body's min size is read with the panel
## UP, which is the stronger claim — it is outside the body's layout.
func _settle(count: int) -> void:
	_panel.visible = true
	_bar.bind_spellbook(_book(count))
	_body.size = Vector2(TRAY_WIDTH, _body.get_combined_minimum_size().y)
	await get_tree().process_frame
	await get_tree().process_frame
	_body.size = Vector2(TRAY_WIDTH, _body.get_combined_minimum_size().y)
	await get_tree().process_frame
	gut.p("%d spells: bar width = %f, rows = %d" % [count, _bar.size.x, _bar.get_row_count()])


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
		# where `set_pressed_no_signal` is a no-op. Open the clickable caster gate
		# by hand; the act gate and the group are what this test is about.
		btn.set_has_caster(true)
	_bar.sync_selected(buttons[3].spell)
	assert_true(buttons[3].button_pressed, "sync_selected marks its button")
	assert_false(buttons[0].button_pressed, "and unmarks the others")


# --- The configure view (#1486): sections, infusion row, affinity line ------

const _GIRDLE: SpellDef = preload("res://attack/spell/defs/girdle.tres")
const _VENOM: SpellDef = preload("res://attack/spell/defs/venom_burst.tres")
const _STUB_ARM := preload("res://test/fixtures/stub_arm.gd")

var _ctl: PlayerInputController
var _plan: MagicAttackPlan


func after_each() -> void:
	if is_instance_valid(_body) and _ctl != null:
		_body.teardown()
	_ctl = null
	_plan = null


## Bind [member _body] over a real controller whose stack holds a magic plan
## casting [param spell] for a caster holding every rostered aspect, INT high
## enough for slots and points to spare.
func _configure(spell: SpellDef) -> void:
	var h := SpellTestHelper.new()
	var graph := h.make_graph([[0, 1]], self)
	var caster := h.make_entity(graph, "ATK", Color.RED)
	var board := caster.stat_board
	board.intelligence.base_value = 400.0
	for aspect in AspectRoster.shared().aspects:
		if aspect.stat != null and board.get_stat(aspect.stat.id) != null:
			board.get_stat(aspect.stat.id).base_value = 5.0
	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.start_turn(caster)
	var bs := BattleSystem.new()
	bs.turn_manager = tm
	bs.graph = graph
	add_child_autofree(bs)
	_ctl = PlayerInputController.new()
	_ctl.graph = graph
	_ctl.turn_manager = tm
	_ctl.battle_system = bs
	_ctl.player = caster
	add_child_autofree(_ctl)
	_body.bind(caster, bs, _ctl)
	_plan = MagicAttackPlan.new()
	_plan.attacker = caster
	_plan.set_spell(spell)
	_ctl.armed_stack.push(_STUB_ARM.new(_plan))
	_panel.visible = false
	_body.size = Vector2(TRAY_WIDTH, _body.get_combined_minimum_size().y)
	await get_tree().process_frame
	await get_tree().process_frame
	_body.size = Vector2(TRAY_WIDTH, _body.get_combined_minimum_size().y)
	await get_tree().process_frame


func _sections() -> Array[SpellTooltipSection]:
	var out: Array[SpellTooltipSection] = []
	for child in _body.get_node("%Sections").get_children():
		if child is SpellTooltipSection:
			out.append(child as SpellTooltipSection)
	return out


func _first_rows() -> Array[Node]:
	var out: Array[Node] = []
	for section in _sections():
		var rows := section.get_node("%Rows")
		out.append(rows.get_child(0) if rows.get_child_count() > 0 else null)
	return out


func test_a_twelve_aspect_configure_view_stays_inside_the_budget() -> void:
	assert_eq(AspectRoster.shared().aspects.size(), 12, "guard: the roster holds 12 aspects")
	var built := SpellSections.build(_GIRDLE)
	for lines in [built.cast, built.on_arrival, built.then, built.crits]:
		assert_false(lines.is_empty(), "guard: girdle fills all four sections")
	await _configure(_GIRDLE)
	var row := _body.get_node("%InfusionRow") as InfusionRow
	assert_true(row.visible, "the infusion row shows")
	assert_eq(row.stepper_ids().size(), 12, "one stepper per held aspect")
	var min_size := _body.get_combined_minimum_size()
	gut.p("12-aspect configure view min size = %s" % min_size)
	assert_lt(min_size.x, MAX_BODY_MIN_WIDTH + 1.0, "min width must stay inside the tray slot")
	assert_lt(min_size.y, MAX_BODY_MIN_HEIGHT + 1.0, "min height must stay inside the tray budget")


func test_the_sections_are_the_builders_lines_and_rebuild_only_on_a_new_spell() -> void:
	await _configure(_GIRDLE)
	var sections := _sections()
	assert_eq(sections.size(), 4, "four section columns")
	var built := SpellSections.build(_GIRDLE, _plan.attacker.stat_board)
	var expected := [built.cast, built.on_arrival, built.then, built.crits]
	for i in mini(sections.size(), 4):
		assert_eq(sections[i].line_texts(), (expected[i] as SpellSections.Lines).lines,
				"section %d is the builder's" % i)
	var before := _first_rows()
	watch_signals(_ctl.armed_stack)
	_plan.state_changed.emit()
	_plan.state_changed.emit()
	assert_signal_emitted(_ctl.armed_stack, "attack_plan_state_changed",
			"guard: the hover path reached the body")
	var after := _first_rows()
	for i in before.size():
		assert_same(after[i], before[i], "an unchanged spell keeps section %d's rows" % i)
		assert_false(before[i] == null or before[i].is_queued_for_deletion(),
				"section %d was not rebuilt" % i)
	_ctl.armed_stack.selected_spell = _VENOM
	assert_eq(_plan.spell, _VENOM, "guard: the stack's pick reaches the plan")
	assert_true(before[0].is_queued_for_deletion(), "a new spell rebuilds the sections")
	await get_tree().process_frame
	var venom := SpellSections.build(_VENOM, _plan.attacker.stat_board)
	assert_eq(_sections()[1].line_texts(), venom.on_arrival.lines, "rebuilt to the new spell")


## #1508: the on-arrival numbers fold through the plan's cast-from node, the
## landing's read node, so a node-local stacks bonus shows; moving the source
## rebuilds the sections.
func test_the_sections_read_through_the_plans_source_node() -> void:
	await _configure(_VENOM)
	var board := _plan.attacker.stat_board
	var graph := _plan.attacker.get_parent() as Graph
	var src := graph.get_skill_nodes()[0]
	SpellTestHelper.new().assign_owner(graph, _plan.attacker, [0])
	var more := StatModifier.new()
	more.stat_id = &"poison_stacks_per_hit"
	more.operation = StatModifier.Operation.MULTIPLY
	more.value = 2.0
	src.add_local_modifier(more)
	var at_node := SpellSections.build(_VENOM, board, src).on_arrival.lines
	assert_ne(at_node, SpellSections.build(_VENOM, board).on_arrival.lines,
			"guard: the node-local bonus moves the on-arrival line")
	_plan.source = src
	_plan.state_changed.emit()
	await get_tree().process_frame
	assert_eq(_sections()[1].line_texts(), at_node, "the tray folds the source node's slice")
