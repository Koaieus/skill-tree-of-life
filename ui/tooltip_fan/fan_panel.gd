@tool
class_name FanPanel
extends Node2D
## Reusable circuit-fan tooltip panel (#223, epic #159). Wraps whatever skin
## Control is hand-placed as its first child — a [GlassPanel] or [HoloPanel]
## instance, authored in-scene like every other panel use in `ui/` — and
## forwards a single `glow` knob to it. Skin choice is "which packed scene is
## instanced as the child", per #215 — not a runtime enum FanPanel owns; swap
## it the same way you'd swap any other panel skin, by editing the child.
## See docs/domain/tooltip-fan.md.
##
## Reveal is driven externally via [method set_progress] against the same
## fixed-clock / `progress(0..1)` contract [FanTrace] already uses — no
## per-component Tween recipes (entry-anim ownership deferred by #215).

## Normalized glow (0..1), forwarded per skin type: directly to [HoloPanel]'s
## own `glow`, or mapped onto [GlassPanel]'s `glow_color` alpha + `glow_strength`.
@export_range(0.0, 1.0, 0.01) var glow: float = 0.3:
	set(v):
		glow = v
		_push_glow()

## Tint used for [GlassPanel]'s glow_color when that's the active skin
## (HoloPanel has no separate tint — its glow is monochrome by design).
@export var glow_tint: Color = Color(0.55, 0.85, 1.0):
	set(v):
		glow_tint = v
		_push_glow()

## Scale the panel starts at when [method set_progress]'s `t` is 0.
@export_range(0.5, 1.0, 0.01) var start_scale: float = 0.82


func _ready() -> void:
	_push_glow()


## First Control child, whichever skin scene was hand-placed under this node.
func get_skin() -> Control:
	for child in get_children():
		if child is Control:
			return child
	return null


func _push_glow() -> void:
	var skin := get_skin()
	if skin == null:
		return
	if skin is HoloPanel:
		(skin as HoloPanel).glow = glow
	elif skin is GlassPanel:
		var panel := skin as GlassPanel
		panel.glow_strength = glow * 40.0
		panel.glow_color = Color(glow_tint.r, glow_tint.g, glow_tint.b, glow)


## Applies the fan reveal at clock position `t` (0..1): cubic ease-out driving
## scale (start_scale → 1.0) and fade (0 → 1). Matches the reveal
## `fan_trace_sandbox.gd` previously hand-rolled per-Dest — callers (the
## sandbox now, the TooltipFan coordinator later, #226) just feed a clock.
func set_progress(t: float) -> void:
	var eased := _ease_out(clampf(t, 0.0, 1.0))
	scale = Vector2.ONE * lerpf(start_scale, 1.0, eased)
	var m := modulate
	m.a = eased
	modulate = m


static func _ease_out(t: float) -> float:
	var inv := 1.0 - t
	return 1.0 - inv * inv * inv
