@tool
class_name ArrowVolleyCoordinator
extends VFXCoordinator

## Ranged-attack volley: one [Projectile] per [member AttackOutcome.hits]
## (i.e. per reaching firing position), all converging on the same target.
## Each shot is staggered by [member stagger_per_shot] so a wide volley
## reads as a flurry of arrival impacts rather than one monolithic THWACK.
##
## Uses the [LightArrow] visual by default — oriented glowing arrow that
## sticks into the target node and fades. Arrows are tinted by the
## attacker's [member Entity.color], read off [member DamageInstance.source]
## (a [RangedAttackPlan], which carries [code]attacker[/code]).

const _DEFAULT_VISUAL: PackedScene = preload("res://ui/vfx/projectile/visual/light_arrow.tscn")

@export var projectile_path: ProjectilePath
@export var visual_scene: PackedScene = _DEFAULT_VISUAL
@export var flight_time: float = 0.45
@export var stagger_per_shot: float = 0.08
@export var face_velocity: bool = true


func play(payload: Variant) -> void:
	var outcome := payload as AttackOutcome
	if outcome == null or outcome.hits.is_empty():
		return
	var tint := _resolve_tint(outcome)
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
		# Tint hook: Projectile.launch instantiates the visual synchronously
		# as its first child. Stamp tint right after so LightArrow reads the
		# attacker colour on first draw. Visuals without a `tint` field
		# ignore the assignment.
		if proj.get_child_count() > 0:
			var v: Node = proj.get_child(0)
			if "tint" in v:
				v.set("tint", tint)
	while pending[0] > 0:
		await get_tree().process_frame


# Resolve attacker tint: the RangedAttackPlan is the hit source and
# carries `attacker: Entity` with a `color`. Defensive — any non-conforming
# source falls back to the LightArrow default.
func _resolve_tint(outcome: AttackOutcome) -> Color:
	for hit in outcome.hits:
		var src: Variant = hit.source
		if src != null and "attacker" in src:
			var atk: Variant = src.attacker
			if atk != null and "color" in atk:
				return atk.color
	return Color(1.0, 0.9, 0.6, 1.0)


func _resolved_path() -> ProjectilePath:
	if projectile_path != null:
		return projectile_path
	return BezierArcPath.new()
