@tool
class_name ModSlabRow
extends Control

## One `StatModifier` rendered as its own mini "glass slab" — a tinted
## background plus a single formatted Label. Part of Tooltip V2 (epic #159
## Phase 0): the fanned-slab layout replaces the tooltip's single scrolling
## modifier list with individually staggered rows, one slab per modifier.
##
## Formatting mirrors `_format_modifier` in `ui/skill_node_tooltip.gd` exactly
## (read-only reference; not shared code — GDScript has no private-function
## import, so keep the two in sync by hand if that convention ever changes):
##   ADD_BASE  -> "+N stat"
##   INCREASE  -> "+N% stat"
##   MULTIPLY  -> "×N stat"
##   ADD_BONUS -> "+N stat (flat)"
##   SET       -> "= N stat"
## Negative values keep their own sign (no leading "+"), e.g. "-3 stat".

## Background tint per operator — the slab's identity color, independent of
## the stat's own `tint_color` (which `skill_node_tooltip.gd` uses for its
## flat list; this is the V2 fan's operator-coded read).
const OPERATOR_TINT: Dictionary = {
	StatModifier.Operation.ADD_BASE: Color(0.32, 0.78, 0.45),
	StatModifier.Operation.INCREASE: Color(0.29, 0.59, 1.0),
	StatModifier.Operation.MULTIPLY: Color(0.69, 0.40, 0.97),
	StatModifier.Operation.ADD_BONUS: Color(0.90, 0.73, 0.27),
	StatModifier.Operation.SET: Color(0.85, 0.30, 0.30),
}

## Subtle "3D-ish" rise: starts slightly small, offset down, and transparent;
## tweens up into resting scale/position/opacity. Kept small on purpose — this
## is a stat-row accent, not a hero animation.
const _ENTRY_START_SCALE := 0.92
const _ENTRY_OFFSET_Y := 10.0
const _ENTRY_DURATION := 0.22

@onready var _background: ColorRect = %Background
@onready var _label: Label = %Label

## Resolved by bind() — exposed so a test can assert the tint without
## re-deriving the per-operator dict lookup itself.
var operator_tint: Color = Color.WHITE
## Resolved by play_entry() — exposed so a test can assert the stagger
## schedule synchronously, without awaiting tween playback.
var entry_delay: float = 0.0

var _entry_tween: Tween = null


## Formats `m` (targeting `stat_name`) into the slab's Label and tints the
## slab background by `m.operation`. See the class docstring for the exact
## per-operator string conventions.
func bind(m: StatModifier, stat_name: String) -> void:
	_label.text = _format_modifier(m, stat_name)
	operator_tint = OPERATOR_TINT.get(m.operation, Color.WHITE)
	_background.color = operator_tint


## Starts this row's staggered entry: waits `index * stagger` seconds, then
## tweens from a slightly scaled-down, offset-down, transparent start into
## resting scale/position/opacity. `entry_delay` is stored up front so a
## headless test can assert the schedule without awaiting playback.
##
## The tween is finite (no `set_loops()`) and targets `self`, so it is bound
## to this node's lifetime — nothing here can hang a test that doesn't await
## it, and a freed row takes its tween with it.
func play_entry(index: int, stagger: float) -> void:
	entry_delay = index * stagger

	pivot_offset = size / 2.0
	var rest_position := position
	var rest_scale := scale
	scale = rest_scale * _ENTRY_START_SCALE
	position = rest_position + Vector2(0.0, _ENTRY_OFFSET_Y)
	modulate.a = 0.0

	if _entry_tween != null and _entry_tween.is_valid():
		_entry_tween.kill()

	_entry_tween = create_tween()
	_entry_tween.tween_interval(entry_delay)
	_entry_tween.set_parallel(true)
	_entry_tween.tween_property(self, "scale", rest_scale, _ENTRY_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_entry_tween.tween_property(self, "position", rest_position, _ENTRY_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_entry_tween.tween_property(self, "modulate:a", 1.0, _ENTRY_DURATION)


## Mirrors `SkillNodeTooltip._format_modifier` — see the class docstring.
func _format_modifier(m: StatModifier, stat_name: String) -> String:
	var _sign := "+" if m.value >= 0.0 else ""
	var val := _val(m.value)
	match m.operation:
		StatModifier.Operation.ADD_BASE:
			return _sign + val + " " + stat_name
		StatModifier.Operation.INCREASE:
			return _sign + val + "% " + stat_name
		StatModifier.Operation.MULTIPLY:
			return "×" + val + " " + stat_name
		StatModifier.Operation.ADD_BONUS:
			return _sign + val + " " + stat_name + " (flat)"
		StatModifier.Operation.SET:
			return "= " + val + " " + stat_name
	return val + " " + stat_name


## Mirrors `SkillNodeTooltip._val`.
func _val(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(v))
	return "%.2f" % v
