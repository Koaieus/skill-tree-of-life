@tool
class_name RangedVolleyCoordinator
extends VFXCoordinator

## Spawns one [Projectile] per [member AttackOutcome.hits], staggered.
## Each projectile applies its hit's damage on [signal Projectile.arrived]
## so floating numbers, hit-flashes, and depletion cascades naturally
## stagger with the visual.

const _DEFAULT_VISUAL: PackedScene = preload("res://ui/vfx/projectile/visual/glowing_dot.tscn")

@export var projectile_path: ProjectilePath
@export var visual_scene: PackedScene = _DEFAULT_VISUAL
@export var flight_time: float = 0.55
@export var stagger_per_shot: float = 0.2
@export var face_velocity: bool = true


# NOTE: `pending` is Array[int] (not bare int) because GDScript lambdas capture
# locals by value — a closure mutating a bare int would not propagate back to
# the loop condition. Single-element array gives the closure something to index.
#
# The counter is decremented on `tree_exiting`, NOT on `arrived`, so the
# coordinator stays alive through every projectile's linger window — without
# that, the dispatcher's `queue_free` after `play()` returns would tear down
# in-flight trails mid-fade.
func play(payload: Variant) -> void:
	var outcome := payload as AttackOutcome
	if outcome == null or outcome.hits.is_empty():
		return
	var pending: Array[int] = [outcome.hits.size()]
	for i in outcome.hits.size():
		var hit: DamageInstance = outcome.hits[i]
		if hit.origin == null or hit.target == null:
			pending[0] -= 1
			continue
		var proj := Projectile.new()
		proj.path = _resolved_path()
		proj.visual_scene = visual_scene
		proj.flight_time = flight_time
		proj.face_velocity = face_velocity
		add_child(proj)
		proj.arrived.connect(func() -> void:
			if hit.target != null:
				hit.target.take_damage(hit.amount, hit))
		proj.tree_exiting.connect(func() -> void:
			pending[0] -= 1)
		proj.launch(
				hit.origin.global_position,
				hit.target.global_position,
				float(i) * stagger_per_shot)
	while pending[0] > 0:
		await get_tree().process_frame


func _resolved_path() -> ProjectilePath:
	if projectile_path != null:
		return projectile_path
	return BezierArcPath.new()
