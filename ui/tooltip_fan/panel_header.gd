@tool
class_name PanelHeader
extends Control

## All-caps label + optional subtext, sat at the top of a content panel.
## Shared row component for Tooltip V2 (epic #159, #293) — split out ahead of
## the content panels (#228/#229/#230/#231) so they don't each mint their own
## copy. See docs/domain/tooltip-fan.md.
##
## An empty subheader COLLAPSES entirely (no reserved blank line) — the
## subheader Label's `visible` is toggled off, and VBoxContainer skips
## invisible children when sizing, so the panel shrinks to the header alone.
##
## Reveal is driven externally via [method set_progress] against the shared
## fixed-clock / `progress(0..1)` contract (see fan_panel.gd / docs/domain/
## tooltip-fan.md) — this node owns no Tween.

## Scale the header starts at when [method set_progress]'s `t` is 0.
@export_range(0.5, 1.0, 0.01) var start_scale: float = 0.9

@onready var _header_label: Label = %HeaderLabel
@onready var _subheader_label: Label = %SubheaderLabel


## Sets the all-caps header text and the optional subheader. An empty (or
## whitespace-only) `subheader` collapses the subheader row entirely.
func bind(header: String, subheader: String = "") -> void:
	_header_label.text = header.to_upper()
	_subheader_label.text = subheader
	_subheader_label.visible = not subheader.is_empty()


## Applies the fan reveal at clock position `t` (0..1): cubic ease-out driving
## scale (start_scale → 1.0) and fade (0 → 1). Matches [method FanPanel.set_progress].
func set_progress(t: float) -> void:
	var eased := _ease_out(clampf(t, 0.0, 1.0))
	scale = Vector2.ONE * lerpf(start_scale, 1.0, eased)
	var m := modulate
	m.a = eased
	modulate = m


static func _ease_out(t: float) -> float:
	var inv := 1.0 - t
	return 1.0 - inv * inv * inv
