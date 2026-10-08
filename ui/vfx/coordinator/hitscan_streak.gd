@tool
class_name HitscanStreak
extends Line2D

## A hitscan line for an aimed cast: its tip runs from the aim's origin along
## the aim to the full [member AttackOutcome.Aim.length] in [param duration]
## seconds — the schedule's lead-in, so it is done by beat 0 — then fades and
## frees itself. Pure picture: it never gates or moves the mutation clock.
##
## The look is the spell's: an aimed spell's coordinator scene instances its
## own copy of `hitscan_streak.tscn` with these knobs set.

signal finished

## Identity colour, SDR; the glow comes from [member glow_tier] alone.
@export var base_color: Color = Emissive.NEUTRAL
## How hot the line burns — a named tier (`.claude/rules/hdr-color.md`).
@export var glow_tier: Emissive.Tier = Emissive.Tier.ALERT
## Line width in pixels.
@export_range(0.5, 32.0, 0.5) var line_width: float = 4.0
## Seconds the full line holds at beat 0 before it starts to fade.
@export_range(0.0, 1.0, 0.01) var hold_seconds: float = 0.05
## Seconds the line takes to fade out after the hold.
@export_range(0.0, 2.0, 0.01) var fade_seconds: float = 0.25


## Draws from [param from] (global) along [param angle] (radians) to
## [param length] pixels over [param duration] seconds, then fades and frees.
func play(from: Vector2, angle: float, length: float, duration: float) -> void:
	global_position = from
	width = line_width
	default_color = Emissive.at(base_color, Emissive.stops(glow_tier))
	var tip := Vector2.from_angle(angle) * length
	points = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	var t := create_tween()
	t.tween_method(func(f: float) -> void:
		set_point_position(1, tip * f), 0.0, 1.0, maxf(duration, 0.0))
	t.tween_interval(hold_seconds)
	t.tween_property(self, ^"modulate:a", 0.0, fade_seconds)
	t.finished.connect(func() -> void:
		finished.emit()
		queue_free())
