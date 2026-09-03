class_name SpellPickerBar
extends HBoxContainer

## Renders the player [SpellBook] as a row of [SpellPickerButton]s. Selecting
## one routes through [signal spell_selected] which UIRoot forwards to
## [member BattleSystem.selected_spell]. The bar self-syncs three independent
## gates on each button (#743, #728): the bar-wide act gate (not your turn / no
## AP — grey AND unclickable), mana against the gating attacker's pool, and
## whether ANY owned node clears the spell's min_degree. The last two go grey
## but STAY clickable so the press can float its own denial — see
## [SpellPickerButton]'s top docstring.
##
## [b]min_degree is a territory question now, not a source question (#728).[/b]
## Before the targeting inversion the bar was fed a pre-picked cast-from node
## and greyed a spell that node could not satisfy. There is no such node any
## more, so the gate asks [method SpellBook.eligible_sources] instead — the same
## predicate [SpellTargetUnion] builds its source set from, so the picker and
## the highlights can never disagree about whether a spell is castable.

signal spell_selected(spell: SpellDef)

const _SpellPickerButton := preload("res://ui/spell_picker_bar/spell_picker_button.tscn")

var _group: ButtonGroup
var _book: SpellBook = null
var _buttons_by_spell: Dictionary[SpellDef, SpellPickerButton] = {}

## Reactive mana regreying (#743) — the picker must grey a spell the instant
## a cast drops the attacker's mana below its cost, not just on the next
## rebuild/reselect. Scoped to whichever attacker [method update_gating_context]
## is currently holding; re-pointed (never accumulated) on every call.
var _mana_subs := SubBag.new()

# The live "who is casting?" context. Set externally by the magic tray body
# from the active MagicAttackPlan; pass null to clear gating. There is no
# companion `_gating_source` since #728 — see this file's top docstring.
var _gating_attacker: Entity = null

# True while the player can act (their turn + AP > 0). When false the bar
# dims and all buttons go uninteractive — UI cue for "no action points left".
var _act_enabled: bool = true


func _ready() -> void:
	_group = ButtonGroup.new()
	_group.allow_unpress = false


## Bind to the player's spellbook. Replaces any previous binding.
func bind_spellbook(book: SpellBook) -> void:
	if _book != null and _book.membership_changed.is_connected(_on_spellbook_changed):
		_book.membership_changed.disconnect(_on_spellbook_changed)
	_book = book
	if _book != null:
		_book.membership_changed.connect(_on_spellbook_changed)
	_rebuild()


func _on_spellbook_changed() -> void:
	_rebuild()


## Highlight the button matching `spell` without firing [signal spell_selected].
func sync_selected(spell: SpellDef) -> void:
	for s in _buttons_by_spell.keys():
		_buttons_by_spell[s].set_selected(s == spell)


## Tell the bar which attacker to gate against. Pass null to clear gating (all
## spells enabled). Took a `source` too until #728 removed the source-selection
## step that supplied one.
func update_gating_context(attacker: Entity) -> void:
	_gating_attacker = attacker
	_resubscribe_mana(attacker)
	_refresh_gating()
	# Propagate caster to buttons so the floating tooltip can compute
	# dynamic values (e.g. cast range scaled by the spell_range / spell_hops
	# stats, #727).
	for btn in _buttons_by_spell.values():
		btn.set_caster(attacker)


## Re-point [member _mana_subs] at [param attacker]'s mana pool so a cast that
## drops it below another spell's cost regreys the picker live, with no
## rebuild/reselect. Always clears first — a bag holds one attacker's worth
## of subscriptions at a time, never accumulates across callers. Uses `on()`
## rather than `now()`: the caller ([method update_gating_context]) already
## runs [method _refresh_gating] right after, so a synchronous first call here
## would just be redundant.
func _resubscribe_mana(attacker: Entity) -> void:
	_mana_subs.clear()
	var mana: PoolStat = attacker.stat_board.mana if attacker != null and attacker.stat_board != null else null
	if mana != null:
		_mana_subs.on(mana.current_changed, _refresh_gating)


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_buttons_by_spell.clear()
	if _book == null:
		return
	if _group == null:
		_group = ButtonGroup.new()
		_group.allow_unpress = false
	for spell in _book.spells:
		if spell == null:
			continue
		var btn: SpellPickerButton = _SpellPickerButton.instantiate()
		btn.spell = spell
		btn.set_caster(_gating_attacker)
		btn.button_group = _group
		btn.spell_picked.connect(_on_spell_button_pressed)
		add_child(btn)
		_buttons_by_spell[spell] = btn
	_refresh_gating()


## Three independent per-spell gates (#743, #728):
## [method SpellPickerButton.set_actionable] (turn/AP — unclickable when unmet),
## [method SpellPickerButton.set_affordable] (mana) and
## [method SpellPickerButton.set_has_caster] (min_degree over the whole owned
## subgraph); the latter two are grey but clickable — see [SpellPickerButton]'s
## top docstring.
##
## `mana_cost` is a flat [member SpellDef.mana_cost] int with no stat pipeline,
## so mana reads the attacker's pool directly. The caster gate delegates to
## [method SpellBook.eligible_sources] rather than re-deriving min_degree here;
## an entity with no spellbook or navigator yields an empty list, which greys
## everything — the same conservative default [SpellBook] already takes.
##
## [param _new_current] is unused — it exists only so this can connect directly
## to [signal PoolStat.current_changed] (1 arg) in [method _resubscribe_mana];
## Godot requires an exact-or-fewer arity match between a signal and the
## callable it invokes, and every other caller here wants zero args anyway.
func _refresh_gating(_new_current: Variant = null) -> void:
	if _book == null:
		return
	var mana: PoolStat = null
	if _gating_attacker != null and _gating_attacker.stat_board != null:
		mana = _gating_attacker.stat_board.mana
	# Dictionary.keys() erases the typed-Dictionary key type back to Variant,
	# so an untyped loop var here makes `spell.mana_cost` a dynamic property
	# read and the `affordable :=` inference below fails to compile — annotate
	# it explicitly.
	for spell: SpellDef in _buttons_by_spell.keys():
		var btn := _buttons_by_spell[spell]
		btn.set_actionable(_act_enabled)
		var affordable := mana == null or spell.mana_cost <= 0 or mana.available() >= spell.mana_cost
		btn.set_affordable(affordable)
		btn.set_has_caster(not _book.eligible_sources(spell, _gating_attacker).is_empty())


## Bar-wide gate. False = no AP / not player's turn; dim the whole bar and
## block input. Keeps per-spell castability authoritative when true.
func set_enabled(enabled: bool) -> void:
	if _act_enabled == enabled:
		return
	_act_enabled = enabled
	modulate.a = 1.0 if enabled else 0.4
	# Per-button disabled state (from _refresh_gating) blocks clicks; the
	# alpha is the visual cue.
	_refresh_gating()


func _on_spell_button_pressed(spell: SpellDef) -> void:
	spell_selected.emit(spell)
