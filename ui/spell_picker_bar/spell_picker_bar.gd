class_name SpellPickerBar
extends HFlowContainer

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
##
## [b]Why [HFlowContainer] and not [HBoxContainer] (#753).[/b] A [Control]'s rect
## is clamped UP to [method Control.get_combined_minimum_size], so anchors lose
## to content min size. An HBox of N fixed 96px buttons has a min width of
## [code]N * 96 + (N - 1) * sep[/code], and the spellbook grows through loot
## without bound — at 8 spells that is already 824px, which shoved the whole
## Command Tray out from under its slot. A flow container's min width is ONE
## button, so the bar can never widen the tray again no matter how big the book
## gets; overflow becomes rows, and the owning body caps those rows at two and
## scrolls past them.
##
## [b]No layout feedback loop.[/b] [method _relayout] picks the button size from
## the bar's *available* width ([member Control.size].x, handed down by the
## tray) versus what the book would need at full size — never from the bar's own
## minimum size. The .tscn pins [member Control.custom_minimum_size].x at
## [constant FULL_BUTTON_PX] so the min width is a constant that the chosen
## button size cannot move, which is what makes the decision a pure function of
## (available width, spell count) rather than a fixed-point search.
##
## [b]Number keys (#718 follow-up).[/b] Tile N carries the keycap for
## `ui_select_spell_N`, derived from its POSITION via
## [method PlayerInputController.spell_keycap] — the book is loot-driven and
## reorders, so nothing here is authored per spell. Spells past the ninth get
## no chip and stay mouse-only; the key handling itself lives in
## [PlayerInputController], gated on MAGIC being the live mode.

signal spell_selected(spell: SpellDef)

## Emitted when [method _relayout] settles on a different row count or button
## size. [MagicBody] listens so it can size the scroll viewport to at most
## [constant MagicBody.MAX_VISIBLE_ROWS] rows of whatever size was chosen.
signal layout_changed(row_count: int, button_px: float)

const _SpellPickerButton := preload("res://ui/spell_picker_bar/spell_picker_button.tscn")

## Button edge while the whole book fits on one row.
const FULL_BUTTON_PX: float = 96.0

## Button edge once the book has to wrap. Owner call (2026-09-04): the Magic
## body is ~180px tall, so two rows of 96 would overflow it — 80 fits.
const COMPACT_BUTTON_PX: float = 80.0

## Horizontal gap between buttons; mirrors the `h_separation` theme constant the
## .tscn authors. Kept as a const because the wrap arithmetic needs it before
## the theme has necessarily resolved (headless, pre-first-frame).
const H_SEPARATION: int = 8

## Vertical gap between wrapped rows.
const V_SEPARATION: int = 4

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

# Last values [method _relayout] settled on, so a re-run that changes nothing
# stays silent. `_layout_published` forces the first emit even when the initial
# (0 rows, 96px) happens to match these defaults.
var _row_count: int = 0
var _button_px: float = FULL_BUTTON_PX
var _layout_published: bool = false


func _ready() -> void:
	_group = ButtonGroup.new()
	_group.allow_unpress = false
	resized.connect(_relayout)


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
	# `_slot` counts the spells actually BUILT, not the loop index — a null
	# hole in the book is skipped, and the digit that skipped tile would have
	# taken belongs to the next real one. Off `PlayerInputController` so the
	# printed glyph and the bound action share one source: a rebind there
	# cannot leave a stale keycap painted here.
	var slot := 0
	for spell in _book.spells:
		if spell == null:
			continue
		var btn: SpellPickerButton = _SpellPickerButton.instantiate()
		btn.spell = spell
		btn.key_hint = PlayerInputController.spell_keycap(slot)
		slot += 1
		btn.set_caster(_gating_attacker)
		btn.button_group = _group
		btn.spell_picked.connect(_on_spell_button_pressed)
		add_child(btn)
		_buttons_by_spell[spell] = btn
	_refresh_gating()
	_relayout()


## Number of wrapped rows the current book occupies at the current width.
func get_row_count() -> int:
	return _row_count


## The button edge currently in force — [constant FULL_BUTTON_PX] or
## [constant COMPACT_BUTTON_PX].
func get_button_px() -> float:
	return _button_px


## Pick the button size from the width the tray is actually giving us, then
## republish the resulting row count. Runs on every resize and after every
## rebuild; both are safe re-entry points because the result depends only on
## (available width, live spell count) and applying it cannot change either —
## see this class's top docstring on why there is no feedback loop.
##
## Idempotent by construction: a second pass over an unchanged (width, count)
## computes the same size, finds nothing to write, and emits nothing.
func _relayout() -> void:
	var buttons := _live_buttons()
	var count := buttons.size()
	var px := FULL_BUTTON_PX
	if count > 1:
		var needed := count * FULL_BUTTON_PX + (count - 1) * H_SEPARATION
		# size.x is 0 before the first layout pass (and in headless tests);
		# that reads as "too narrow", which is the safe/bounded branch.
		if size.x < needed:
			px = COMPACT_BUTTON_PX
	var per_row := 1
	if count > 0:
		per_row = maxi(1, int(floorf((size.x + H_SEPARATION) / (px + H_SEPARATION))))
	var rows := 0 if count == 0 else int(ceilf(float(count) / float(per_row)))
	var px_changed := not is_equal_approx(px, _button_px)
	if px_changed:
		for btn in buttons:
			btn.custom_minimum_size = Vector2(px, px)
	if _layout_published and not px_changed and rows == _row_count:
		return
	_button_px = px
	_row_count = rows
	_layout_published = true
	layout_changed.emit(rows, px)


## Children minus the ones [method _rebuild] has already queued for deletion —
## they linger in [method Node.get_children] until the frame ends and would
## double the count the wrap arithmetic sees.
func _live_buttons() -> Array[SpellPickerButton]:
	var out: Array[SpellPickerButton] = []
	for child in get_children():
		if child is SpellPickerButton and not child.is_queued_for_deletion():
			out.append(child as SpellPickerButton)
	return out


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
