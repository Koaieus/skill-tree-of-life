@tool
class_name LeafblowerRebound
extends Node2D

## Leafblower's crit-only "backwash" companion (#676) — the gust hit a dead
## end and splashed back. Fires ONLY when the arrival carries a crit tier
## ([LeafCritCondition]: the target's own territory degree is 1, at most
## 2-3 impacts per cast); an ordinary arrival leaves this a silent no-op that
## reports done immediately, so it never becomes ~25 one-shot systems per
## cast. Nothing else in the game bounces backward, which is what makes the
## cul-de-sac read unambiguous.
##
## Not emissive — leaf debris and wind, not spellcraft, matching [DustPuff]'s
## own "no [Emissive] call" precedent (#672). The standard red crit grammar
## (retint + ring) already carries the "this was special" signal; this
## companion only carries the "and it was a DEAD END" signal.
##
## [b]Direction is read off [method _on_context]'s [code]entry.origin[/code] /
## [code]entry.target[/code] world positions, never off this node's own
## rotation.[/b] A [Projectile] with [code]face_velocity[/code] on rotates
## ITSELF to face travel, and this node inherits that as a parent transform —
## so [member Node2D.global_rotation] is the only write that lands in world
## space regardless of what the parent happens to be doing.

signal finished

@onready var _particles: CPUParticles2D = %Particles

var _crit_tier: int = 0
## Origin → target, world-space, normalized. The burst fires the OPPOSITE way
## — "back along the arrival direction" — computed at fire time so a stale
## zero vector (no context ever arrived) degenerates to "no rotation" rather
## than a divide-by-zero.
var _travel_direction: Vector2 = Vector2.ZERO


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_particles.emitting = false


func _on_context(entry: Variant) -> void:
	_travel_direction = _read_travel_direction(entry)


func _on_crit(tier: int) -> void:
	_crit_tier = tier


func _on_arrival() -> void:
	if Engine.is_editor_hint():
		return
	if _crit_tier <= 0:
		# Ordinary arrival — the whole point of the gate. Already done.
		finished.emit()
		queue_free()
		return
	if _travel_direction != Vector2.ZERO:
		_particles.global_rotation = (-_travel_direction).angle()
	_particles.restart()
	_particles.emitting = true
	var t := create_tween()
	t.tween_interval(_particles.lifetime)
	t.tween_callback(func() -> void:
		finished.emit()
		queue_free())


## [code]entry.origin[/code] → [code]entry.target[/code] as a world-space unit
## vector. [Variant]-typed and read defensively for the same reason every
## other visual in this directory is: the duck-typed contract must keep
## working for a caller that hands over a shape this companion doesn't
## recognize.
func _read_travel_direction(entry: Variant) -> Vector2:
	if not (entry is Object):
		return Vector2.ZERO
	var obj: Object = entry
	if not ("origin" in obj and "target" in obj):
		return Vector2.ZERO
	var origin: Object = obj.get("origin")
	var target: Object = obj.get("target")
	if not (origin is Node2D and target is Node2D):
		return Vector2.ZERO
	var delta: Vector2 = target.global_position - origin.global_position
	if delta.length_squared() < 1e-6:
		return Vector2.ZERO
	return delta.normalized()
