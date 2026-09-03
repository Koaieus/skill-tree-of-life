extends GutTest

## #743 — the spell picker greys a spell the entity can't afford (mana) while
## keeping it clickable, floats "GEEN MANA MEER" through [signal
## Events.ui_action_denied] on a click instead of selecting it, and regreys
## LIVE when a cast drops mana below another spell's cost — no rebuild, no
## reselect. Complements test_denial_toast.gd (the node-anchored sibling
## path); this pins the widget-anchored one Events.ui_action_denied adds.
##
## Deliberately builds its own SpellDefs with arbitrary costs rather than
## reading a shipped SpellCatalog entry — the owner's mana numbers are tuning,
## not something a test should pin (.claude/rules — "owner tunes, agents
## test"). min_degree stays 0 throughout and every button is gated with a
## null source, so [method SpellBook.is_castable] never engages — this file
## tests the mana axis in isolation, same boundary the owner drew against
## #728 (mana_cost is source-independent).

const _BAR_SCENE := preload("res://ui/spell_picker_bar/spell_picker_bar.tscn")
const _DEFAULT_BOARD := preload("res://entity/default_entity_board.tres")

var _bar: SpellPickerBar
var _entity: Entity
var _book: SpellBook
var _cheap_spell: SpellDef
var _pricey_spell: SpellDef
var _denials: Array


func before_each() -> void:
	_entity = Entity.new()
	_entity.display_name = "Caster"
	_entity.stat_board = _DEFAULT_BOARD.duplicate(true) as EntityStatBoard
	add_child_autofree(_entity)
	# Pin a known, arbitrary starting pool rather than whatever the authored
	# board ships — the exact number is a fixture concern, not owner tuning.
	# MUST run after add_child: Entity._ready() tops every pool to full, which
	# would silently clobber a `.current` set beforehand.
	_entity.stat_board.mana.current = 6.0

	_cheap_spell = SpellDef.new()
	_cheap_spell.name = "Cheap"
	_cheap_spell.mana_cost = 5
	_cheap_spell.min_degree = 0

	_pricey_spell = SpellDef.new()
	_pricey_spell.name = "Pricey"
	_pricey_spell.mana_cost = 8
	_pricey_spell.min_degree = 0

	_book = SpellBook.new()
	_book.learn(_cheap_spell)
	_book.learn(_pricey_spell)

	_bar = _BAR_SCENE.instantiate() as SpellPickerBar
	add_child_autofree(_bar)
	_bar.bind_spellbook(_book)
	_bar.update_gating_context(_entity, null)

	_denials = []
	Events.ui_action_denied.connect(_on_ui_action_denied)


func after_each() -> void:
	if Events.ui_action_denied.is_connected(_on_ui_action_denied):
		Events.ui_action_denied.disconnect(_on_ui_action_denied)


func _on_ui_action_denied(anchor: Node2D, reason: String) -> void:
	_denials.append({"anchor": anchor, "reason": reason})


func _btn(spell: SpellDef) -> SpellPickerButton:
	for child in _bar.get_children():
		if child is SpellPickerButton and (child as SpellPickerButton).spell == spell:
			return child as SpellPickerButton
	return null


func test_unaffordable_spell_greys_but_stays_clickable() -> void:
	var btn := _btn(_pricey_spell)
	assert_not_null(btn)
	assert_false(btn.disabled, "mana gate must not use `disabled` — a disabled Button swallows the click the denial needs")


func test_affordable_spell_is_not_greyed() -> void:
	var btn := _btn(_cheap_spell)
	assert_false(btn.disabled)
	# Affordable and castable (source null never gates min_degree) — toggle_mode
	# stays on, same as before #743 touched anything.
	assert_true(btn.toggle_mode)


func test_click_on_unaffordable_spell_denies_and_does_not_select() -> void:
	var selected: Array[SpellDef] = []
	_bar.spell_selected.connect(func(s: SpellDef): selected.append(s))

	_btn(_pricey_spell)._on_pressed()

	assert_eq(selected.size(), 0, "an unaffordable pick must never emit spell_selected")
	assert_eq(_denials.size(), 1)
	assert_eq(_denials[0]["reason"], "spell_denied_no_mana")
	assert_true(is_instance_valid(_denials[0]["anchor"]), "the denial must anchor at a live node")


func test_click_on_affordable_spell_selects_and_denies_nothing() -> void:
	var selected: Array[SpellDef] = []
	_bar.spell_selected.connect(func(s: SpellDef): selected.append(s))

	_btn(_cheap_spell)._on_pressed()

	assert_eq(selected, [_cheap_spell])
	assert_eq(_denials.size(), 0)


func test_unaffordable_button_is_not_toggle_capable() -> void:
	# Cheap (affordable, unselected) stays toggle-capable — the normal click
	# flow is untouched by #743.
	assert_true(_btn(_cheap_spell).toggle_mode)
	# Pricey (unaffordable, unselected) is NOT. This is the actual fix: Godot's
	# ButtonGroup exclusivity (unpress the sibling, commit button_pressed on
	# the clicked one) runs synchronously inside native click processing,
	# before any signal handler gets a chance to veto it — a toggle_mode=true
	# unaffordable button would steal the highlight from the real selection
	# with nothing able to hand it back. toggle_mode=false means Godot's own
	# click handling never touches button_pressed/the group for this button at
	# all — nothing to steal, nothing to revert.
	assert_false(_btn(_pricey_spell).toggle_mode)


func test_casting_drops_mana_and_regreys_live_without_rebuild_or_reselect() -> void:
	var cheap_btn := _btn(_cheap_spell)
	var pricey_btn := _btn(_pricey_spell)
	assert_false(pricey_btn.disabled)
	# Sanity: pricey (cost 8) is unaffordable at mana 6, cheap (cost 5) is not.
	assert_true(cheap_btn.toggle_mode)

	# Raise mana above both costs, then drop it via the pool's own transfer
	# method (mirrors how BattleSystem._commit pays for a cast:
	# `mana_pool.deplete(...)`) so `current_changed` fires exactly as it would
	# from a real launch — no bar rebuild, no reselect in between.
	_entity.stat_board.mana.current = 9.0
	assert_true(cheap_btn.toggle_mode, "affordable again above both costs")

	_entity.stat_board.mana.deplete(4.0)  # 9 -> 5: now only the cheap spell fits

	assert_true(cheap_btn.toggle_mode, "still affordable at exactly its cost")
	assert_false(pricey_btn.toggle_mode, "regreyed live off the pool signal, no rebuild/reselect")


func test_selected_spell_keeps_its_highlight_after_becoming_unaffordable() -> void:
	var cheap_btn := _btn(_cheap_spell)
	# Select the cheap spell while it's still affordable — the same
	# button_pressed + toggled sequence test_loot_picker.gd uses to drive a
	# real ButtonGroup commit from script (a plain `pressed.emit()` never
	# touches button_pressed at all, only the native click path does).
	cheap_btn.button_pressed = true
	cheap_btn.toggled.emit(true)
	assert_true(cheap_btn.button_pressed)

	# Drain mana below the SELECTED spell's own cost via a real cast-shaped
	# deplete — the model (BattleSystem.selected_spell, mirrored here by the
	# fact nothing reselected) never changed, so the view must not silently
	# desync from it.
	_entity.stat_board.mana.deplete(3.0)  # 6 -> 3, below the cheap spell's cost of 5

	assert_true(cheap_btn.button_pressed, "the highlight must survive its own spell going unaffordable")
	assert_true(cheap_btn.toggle_mode, "kept toggle-capable so the button_pressed carve-out in _refresh_toggle_mode holds")

	# Re-clicking the now-unaffordable-but-still-selected spell is a
	# legitimate "why can't I recast this" moment — it must re-float the
	# denial, not silently no-op.
	cheap_btn._on_pressed()
	assert_eq(_denials.size(), 1)
	assert_eq(_denials[0]["reason"], "spell_denied_no_mana")
