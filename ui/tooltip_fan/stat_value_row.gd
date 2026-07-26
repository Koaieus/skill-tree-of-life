@tool
class_name StatValueRow
extends Control

## Stat name label + formatted value, aligned, tinted by the [StatDef]'s
## `tint_color`. Shared row component for Tooltip V2 (epic #159, #293) — split
## out ahead of the content panels (#228/#230/#231). See docs/domain/tooltip-fan.md.
##
## Renders three independent forms — pick the bind method matching the data:
##   [method bind_scalar]        "+5"      — a single signed value
##   [method bind_pool]          "6 / 10"  — current / max, never a bar
##   [method bind_parenthetical] "5 (3)"   — a value with a bracketed second
##                                            reading (e.g. armor + min_damage_taken)
##
## Carries a hidden [TextureRect] icon slot (`%Icon`, `visible = false`) so the
## icon pipeline (#210) is later a single texture assignment in one scene —
## nothing here needs to change to light it up.
##
## Reveal is driven externally via [method set_progress] against the shared
## fixed-clock / `progress(0..1)` contract — this node owns no Tween.

## Scale the row starts at when [method set_progress]'s `t` is 0.
@export_range(0.5, 1.0, 0.01) var start_scale: float = 0.92

@onready var _icon: TextureRect = %Icon
@onready var _name_label: Label = %NameLabel
@onready var _value_label: Label = %ValueLabel


## Scalar form: a single signed value, e.g. `+5` / `-3`.
func bind_scalar(stat_def: StatDef, value: float) -> void:
	_bind_name(stat_def)
	var sign := "+" if value >= 0.0 else ""
	_value_label.text = sign + _val(value)


## Pool form: `current / max`, e.g. `6 / 10`. Never falls back to a bar —
## callers wanting a bar own that decision elsewhere.
func bind_pool(stat_def: StatDef, current: float, max_value: float) -> void:
	_bind_name(stat_def)
	_value_label.text = "%s / %s" % [_val(current), _val(max_value)]


## Suffixed/parenthetical form: a primary value with a bracketed secondary
## reading, e.g. `5 (3)` — #230's combined armor + min_damage_taken row.
func bind_parenthetical(stat_def: StatDef, value: float, paren_value: float) -> void:
	_bind_name(stat_def)
	_value_label.text = "%s (%s)" % [_val(value), _val(paren_value)]


## Applies the fan reveal at clock position `t` (0..1): cubic ease-out driving
## scale (start_scale → 1.0) and fade (0 → 1). Matches [method FanPanel.set_progress].
func set_progress(t: float) -> void:
	var eased := _ease_out(clampf(t, 0.0, 1.0))
	scale = Vector2.ONE * lerpf(start_scale, 1.0, eased)
	var m := modulate
	m.a = eased
	modulate = m


func _bind_name(stat_def: StatDef) -> void:
	_name_label.text = stat_def.display_name
	_name_label.add_theme_color_override("font_color", stat_def.tint_color)


## Render a float without trailing ".00" — whole values print as ints.
## Mirrors [method ModSlabRow._val].
static func _val(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(v))
	return "%.2f" % v


static func _ease_out(t: float) -> float:
	var inv := 1.0 - t
	return 1.0 - inv * inv * inv
