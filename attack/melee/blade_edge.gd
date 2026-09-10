@tool
class_name BladeEdge
extends Node2D

## Pure visual — draws a line between two BladeNodes, trimmed to each rim.
## No collision; hit detection is handled by BladeHitScan against the
## simulated trajectory, not by Godot overlap.

signal endpoints_changed

@export var from: BladeNode:
	set(value):
		from = value
		endpoints_changed.emit()
		queue_redraw()

@export var to: BladeNode:
	set(value):
		to = value
		endpoints_changed.emit()
		queue_redraw()

## Look profile (#256) — width and tier come from here, same resource the
## endpoints draw from. Falls back to [constant BladeNode.DEFAULT_STYLE].
@export var style: BladeStyle = null:
	set(value):
		style = value
		queue_redraw()

## The wielder's identity colour, blended per [member BladeStyle.entity_tint].
@export var tint: Color = Color.TRANSPARENT:
	set(value):
		tint = value
		queue_redraw()

## Set directly by [SkillBlade] once THIS edge itself has broken (#781's
## bunker structural break) — independent of [method is_disabled]'s endpoint
## read below, because ADR 0005 severs an edge while BOTH the vertices it
## hangs off survive ("bunkers destroy structure, never matter"). There is
## nothing on either endpoint to read this off of; it has to be told.
@export var severed: bool = false:
	set(value):
		severed = value
		queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


## Reads only [member severed] (#787's structural break, #781's future
## caller) — untouched by this issue per the owner's decision 8. An endpoint
## DEATH used to de-lit through this same predicate; it now drives its own
## fuse-burn draw off [method death_progress] instead, so it is no longer
## folded in here. There is still no second copy of "who is dead": the
## endpoint half reads live off [BladeNode.death_progress], which itself
## reads off [BladePopResolver.Result.dead_at] every frame.
func is_disabled() -> bool:
	return severed


## The endpoint-death ramp this edge draws its fuse-burn against: the higher
## of its two ends' own [member BladeNode.death_progress]. Not stored — a pure
## read of the live endpoints, so it can never go stale relative to them.
func death_progress() -> float:
	var a := from.death_progress if from != null else 0.0
	var b := to.death_progress if to != null else 0.0
	return maxf(a, b)


func _draw() -> void:
	if from == null or to == null:
		return
	var a := to_local(from.edge_point(to.global_position))
	var b := to_local(to.edge_point(from.global_position))
	if (b - a).length_squared() < 0.01:
		return
	var s: BladeStyle = style if style != null else BladeNode.DEFAULT_STYLE
	if severed:
		# #781's structural break — visually unchanged from the old bool
		# `disabled` de-lit (owner decision 8: "leave the severed branch
		# visually unchanged").
		draw_line(a, b, s.edge_color(tint, true), s.edge_width, true)
		return
	var p := death_progress()
	if p >= 1.0:
		return  # fully burned away
	if p <= 0.0:
		draw_line(a, b, s.edge_color(tint, false), s.edge_width, true)
		return
	_draw_fuse_burn(a, b, p, s)


## "The line erodes from B's end toward its surviving endpoint with a bright
## travelling tip, thinning to nothing" (owner decision 7). `a`/`b` are
## RECOMPUTED every frame from the live endpoints (never snapshotted at pop
## time, per decision 7) — a coasting fragment keeps stretching the line as it
## drifts, exactly like a still-driven one.
func _draw_fuse_burn(a: Vector2, b: Vector2, progress: float, s: BladeStyle) -> void:
	var dead_is_from := (from.death_progress if from != null else 0.0) \
			>= (to.death_progress if to != null else 0.0)
	var dead_point := a if dead_is_from else b
	var live_point := b if dead_is_from else a
	var tip := dead_point.lerp(live_point, progress)
	var color := s.edge_color(tint, false)
	color.a *= 1.0 - progress
	draw_line(tip, live_point, color, s.edge_width, true)
	# A brighter travelling tip marks the burn front.
	var tip_color := Emissive.at(s.base_for(false, tint), Emissive.ALERT)
	tip_color.a *= 1.0 - progress
	draw_circle(tip, s.edge_width * 0.9, tip_color)
