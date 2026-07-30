class_name HpReadout
extends Control

## Tooltip V2 (epic #159 Phase 0) HP readout widget.
##
## Wraps the shared LabeledProgressBar (res://ui/labeled_progress_bar.gd —
## same bar StatsPanel uses) behind a single `set_hp()` entry
## point, and exposes a `placement` enum so the same widget can be dropped
## into four different tooltip-fan spots (header row, above-node caption,
## ID-chip corner, node-ring badge) without a bespoke bar per spot.
##
## Tint ramp is the node-HP red->green ramp the V1 tooltip used
## (`skill_node_tooltip.gd::_populate_hp`, deleted by #235) — replicated
## exactly, not re-derived: `Color.from_hsv(lerpf(0.0, 0.33, ratio), 0.9, 1.0)`.
##
## NOTE (#235): no panel or unit in `fan.tscn` mounts this widget — it is
## unreferenced Phase-0 work (#220). Kept deliberately: #314 gave the fan live HP
## updates rendered as numeric rows, and this is the pre-built bar if a future
## issue wants the bar form back. Delete it, don't adopt it half-way.

enum Placement { HEADER, ABOVE, CHIP, RING }

@export var placement: Placement = Placement.HEADER:
	set(value):
		placement = value
		_apply_placement()

@onready var _caption: Label = $CaptionLabel

var _bar: LabeledProgressBar


func _ready() -> void:
	_ensure_bar()
	_apply_placement()


func set_hp(current: float, maximum: float) -> void:
	_ensure_bar()
	var ratio: float = clampf(current / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0
	var tint := Color.from_hsv(lerpf(0.0, 0.33, ratio), 0.9, 1.0)
	var text := "%s/%s" % [int(round(current)), int(round(maximum))]
	_bar.set_values(text, current, maximum, tint)
	if _caption != null:
		_caption.text = text


## Read the tint the wrapped bar was last painted with — same value the
## acceptance test checks, exposed so callers don't have to reach into `_bar`.
func get_tint() -> Color:
	return _bar.self_modulate if _bar != null else Color.WHITE


func _ensure_bar() -> void:
	if _bar != null:
		return
	_bar = LabeledProgressBar.create()
	add_child(_bar)


func _apply_placement() -> void:
	if _bar == null or _caption == null:
		return
	match placement:
		Placement.HEADER:
			# Horizontal, label inline, full-width bar.
			custom_minimum_size = Vector2(180.0, 24.0)
			size = custom_minimum_size
			_caption.visible = false
			_bar.label.visible = true
			_bar.position = Vector2.ZERO
			_bar.size = Vector2(180.0, 24.0)
		Placement.ABOVE:
			# VBox-style: small centered label ABOVE a thinner bar.
			custom_minimum_size = Vector2(120.0, 34.0)
			size = custom_minimum_size
			_caption.visible = true
			_caption.position = Vector2.ZERO
			_caption.size = Vector2(120.0, 16.0)
			_bar.label.visible = false
			_bar.position = Vector2(0.0, 18.0)
			_bar.size = Vector2(120.0, 8.0)
		Placement.CHIP:
			# Compact minimal-width bar, "cur/max" overlaid, for an ID-chip corner.
			custom_minimum_size = Vector2(48.0, 14.0)
			size = custom_minimum_size
			_caption.visible = false
			_bar.label.visible = true
			_bar.position = Vector2.ZERO
			_bar.size = Vector2(48.0, 14.0)
		Placement.RING:
			# Small square footprint, short/compact bar to tuck near the node ring.
			custom_minimum_size = Vector2(32.0, 10.0)
			size = custom_minimum_size
			_caption.visible = false
			_bar.label.visible = false
			_bar.position = Vector2.ZERO
			_bar.size = Vector2(32.0, 10.0)
