@tool
class_name ArrowVolleyCoordinator
extends VFXCoordinator

## Ranged-attack volley: one [Projectile] per [member AttackOutcome.hits]
## (i.e. per reaching firing position), all converging on the same target.
## Each shot is staggered by [member stagger_per_shot] so a wide volley
## reads as a flurry of arrival impacts rather than one monolithic THWACK.
##
## Pure observer (#474) — [member AttackOutcome.hits] has ALREADY landed by
## the time [method play] runs (BattleSystem applies it synchronously before
## any VFX await). This coordinator never calls take_damage; it only renders.
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
		pending[0] += 1
		_show_presentation(hit, pending)
	while pending[0] > 0:
		await get_tree().process_frame


## Fires the presentation-clock reveal (#479/#481) on [member
## DamageInstance.arrival_time] — the shot's real distance/speed timing
## (#480), independent of this coordinator's own [member flight_time] /
## [member stagger_per_shot] visual tuning. Pure observer: damage already
## landed synchronously in BattleSystem._apply_outcome (#474) before [method
## play] ever ran; this only tells presentation-only subscribers (HP bar,
## node tint, death VFX) when the shot visually arrived. Included in
## `pending` so [method play] doesn't return (and get torn down by
## [AttackVFX]) before this fires.
func _show_presentation(hit: DamageInstance, pending: Array[int]) -> void:
	if hit.arrival_time > 0.0:
		await get_tree().create_timer(hit.arrival_time).timeout
	Events.damage_shown.emit(hit.target, hit.amount)
	if not hit.target.is_allocated():
		Events.node_death_shown.emit(hit.target)
	pending[0] -= 1


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
