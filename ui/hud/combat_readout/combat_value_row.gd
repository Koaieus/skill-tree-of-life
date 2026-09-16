@tool
class_name CombatValueRow
extends HBoxContainer
## One "Label: Value" line in a Combat Readout card, with a [DeltaChip] that
## pops whenever [method set_value] sees the number change, plus an optional
## breakpoint sliver caption underneath (e.g. "+1 / 20 STR - next @60").
##
## #119 — also supports a persistent "this value is overridden" display mode
## ([method show_override]/[method clear_override]), used when hovering a
## SkillNode whose local stat differs from the entity baseline. Deliberately
## NOT the [DeltaChip] — that's a 2.7s transient pop for a stat CHANGING;
## this is a held state for as long as the node stays hovered, and needs to
## coexist with (not fight) normal baseline updates arriving mid-hover.

@onready var _label: Label = %Label
@onready var _value: Label = %Value
@onready var _sliver: Label = %Sliver
@onready var _chip: DeltaChip = %DeltaChip
@onready var _override_badge: Label = %OverrideBadge

@export var row_label: String = "":
	set(v):
		row_label = v
		if _label != null:
			_label.text = v

## Which board stat this row displays (#729) — resolves a [StatDef] for the
## chip's polarity colouring. Empty for a row that isn't a real stat (a
## derived value like Combat Card Magic's potency/reach), which leaves the
## chip on its old sign-only colouring.
@export var stat_id: StringName = &""

## ALERT tier (#390) — a node-local override is exactly the "genuine
## punctuation" the tier vocabulary reserves ALERT for: the value differs
## from baseline right now.
@export var override_color: Color = Emissive.at(Color(0.9, 0.75, 0.4), Emissive.ALERT)

## Fixed decimal places rendered in [method _render]. Default 0 keeps every
## existing row's whole-number look; a row displaying a fine-grained stat
## (e.g. crit chance/multiplier) can opt into more precision.
@export_range(0, 4, 1) var decimals: int = 0

## Appended after the rendered number ("%", " px", "x") — same string on the
## baseline and on an override, so the two stay comparable on screen. Applied
## by [method refresh]; a row that isn't self-binding (no [member stat_id])
## still takes a suffix per-call via [method set_value] instead.
@export var suffix: String = ""

## Multiplies the raw board value before display (#913 — e.g. `crit_chance`'s
## 0..1 fraction becomes a whole percent with `value_scale = 100.0`). Applied
## to both the baseline and a node-local override in [method
## _on_stat_changed] so the two never drift out of the same units. Named
## `value_scale`, not `scale` — [Control] already owns that property (the
## node's own visual scale), and redeclaring it is a parse error, not a
## shadow.
@export var value_scale: float = 1.0

var _last_value: float = NAN
var _last_suffix: String = ""
var _override_active: bool = false
var _override_value: float = 0.0

var _delta_baseline: float = NAN
var _flush_delta_deferred := DeferredOnce.new(_flush_delta)

## #913 — self-binding state. [member _bound_board] gates re-linking
## [signal Stat.value_changed] to only when the board actually changes (a
## hot-seat rebind), never on every [method refresh] call — that call also
## happens FROM inside the signal's own emission (see [method
## _on_stat_changed]), so an unconditional clear+relink there would disconnect
## and reconnect mid-emission for no reason. [member _bound_hover_node] is
## cached because [SubBag] delivers [method _on_stat_changed] with zero
## arguments (see its doc) — the hover state has to come from somewhere else.
var _bound_board: StatBoard = null
var _bound_hover_node: SkillNode = null
var _sub := SubBag.new()

func _ready() -> void:
	if _label != null:
		_label.text = row_label
	if _sliver != null:
		_sliver.visible = false
	if _override_badge != null:
		_override_badge.visible = false


## #913 — makes the row self-binding: (re-)links [signal Stat.value_changed]
## for [member stat_id] on [param board] (only when [param board] differs
## from the last one bound — see [member _bound_board]'s doc) and renders the
## current baseline plus, if [param hover_node] is an owned node whose local
## value for [member stat_id] differs from that baseline, the override. A row
## with no [member stat_id] (a derived value the card computes itself, e.g.
## Magic's potency/reach) is a no-op — the card still drives those directly
## via [method set_value].
func refresh(board: StatBoard, hover_node: SkillNode) -> void:
	if stat_id == &"":
		return
	_bound_hover_node = hover_node
	if board != _bound_board:
		_sub.clear()
		_bound_board = board
		if board != null:
			var stat := board.get_stat(stat_id)
			if stat != null:
				_sub.on(stat.value_changed, _on_stat_changed)
	_on_stat_changed()


## The [SubBag]-connected callback (zero args, per its doc) AND [method
## refresh]'s own render step — reads [member _bound_board]/[member
## _bound_hover_node] rather than trusting a signal argument, since a bare
## [signal Stat.value_changed] carries none anyway.
func _on_stat_changed() -> void:
	if _bound_board == null:
		return
	var stat := _bound_board.get_stat(stat_id)
	var baseline: float = float(stat.value) if stat != null else 0.0
	set_value(baseline * value_scale, suffix)
	var ov: Variant = resolve_override(_bound_hover_node, _bound_board, baseline)
	if ov != null:
		show_override(float(ov) * value_scale)
	else:
		clear_override()


## Node-local override lookup (#119, moved off [CombatReadoutCard] in #913 so
## every row — self-bound via [method refresh] or card-pushed, like Ranged's
## scaled rows — shares one implementation). `null` unless [param hover_node]
## is owned by the same entity [param board] belongs to (compared via
## `stat_board`, since a [StatBoard] carries no owner backpointer of its own —
## see [method CombatReadoutCard.bind]'s doc) AND its local value for [member
## stat_id] differs from [param baseline].
func resolve_override(hover_node: SkillNode, board: StatBoard, baseline: float) -> Variant:
	if hover_node == null or board == null or stat_id == &"":
		return null
	if hover_node.owned_by == null or hover_node.owned_by.stat_board != board:
		return null
	var overridden: float = float(hover_node.get_local_value(stat_id))
	return overridden if overridden != baseline else null


func set_value(v: float, suffix: String = "") -> void:
	if not _flush_delta_deferred.is_queued():
		_delta_baseline = _last_value
	_flush_delta_deferred.request()
	_last_value = v
	_last_suffix = suffix
	_render()


func _flush_delta() -> void:
	if is_nan(_delta_baseline) or _override_active or _chip == null:
		return
	var shown := _rendered(_last_value)
	var was := _rendered(_delta_baseline)
	if shown == was:
		return
	var def: StatDef = StatRegistry.get_def(stat_id) if stat_id != &"" else null
	_chip.pop(shown.to_float() - was.to_float(), decimals, _last_suffix, def)


## Renders at the row's own [member decimals] precision — same rule as
## [method _render], minus the suffix (identical on both sides of a delta,
## so it can't be what makes the strings differ). The chip shows the
## difference of THESE, not of the raw floats, so a sub-precision delta
## (e.g. +0.4 on a 0-decimal row) never fires the chip and the chip always
## agrees with the two values the player actually saw.
func _rendered(v: float) -> String:
	return ("%." + str(decimals) + "f") % v


func set_sliver(text: String) -> void:
	if _sliver == null:
		return
	_sliver.visible = not text.is_empty()
	_sliver.text = text


## Persistently displays `overridden` instead of the last baseline
## [method set_value], with distinct styling + a small badge. Caller (the
## combat card) only invokes this for rows whose node-local value actually
## differs from baseline — equal-valued rows should call [method
## clear_override] instead so unchanged stats don't light up.
func show_override(overridden: float) -> void:
	_override_active = true
	_override_value = overridden
	_render()


## Reverts to the last baseline value/suffix set via [method set_value].
func clear_override() -> void:
	if not _override_active:
		return
	_override_active = false
	_render()


func _render() -> void:
	if _value == null:
		return
	var fmt := "%." + str(decimals) + "f%s"
	if _override_active:
		_value.text = fmt % [_override_value, _last_suffix]
		_value.add_theme_color_override(&"font_color", override_color)
	else:
		_value.text = fmt % [_last_value, _last_suffix]
		_value.remove_theme_color_override(&"font_color")
	if _override_badge != null:
		_override_badge.visible = _override_active
