@tool
class_name DustPuff
extends Node2D

## Bruiser's one-shot ground-impact burst (#672) — the "thud" companion
## alongside [ImpactRing] in a [ComposedProjectileVisual]. Affordable
## specifically because Bruiser peaks at ONE simultaneous cast (#663's load
## table); no other spell in the kit should reach for [CPUParticles2D] on
## this precedent.
##
## Not emissive — dust and debris, not spellcraft, so it carries no HDR tier
## and needs no [Emissive] call. Arrival-only: no `_on_launch` / `_on_progress`
## in the duck contract, matching [ImpactRing]'s own "punctuation, not travel"
## shape.

signal finished

@onready var _particles: CPUParticles2D = %Particles


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_particles.emitting = false


func _on_arrival() -> void:
	if Engine.is_editor_hint():
		return
	_particles.restart()
	_particles.emitting = true
	var t := create_tween()
	t.tween_interval(_particles.lifetime)
	t.tween_callback(func() -> void:
		finished.emit()
		queue_free())
