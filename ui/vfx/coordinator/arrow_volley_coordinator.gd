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
## Floor on a shot's airtime, as a fraction of [member flight_time] — a
## point-blank shot still needs enough frames to read as an arrow.
const MIN_FLIGHT_FRACTION: float = 0.4

## Fallback airtime for a shot with no [member DamageInstance.arrival_time],
## and (scaled by [constant MIN_FLIGHT_FRACTION]) the floor for one that has.
@export var flight_time: float = 0.45
## Launch spacing between shots. Defaults to the domain stagger so VFX
## launches and the recorded timeline share one source of truth — an override
## retempos only the launches (the reveal still rides the recorded
## [member DamageInstance.arrival_time], so the single clock holds).
@export var stagger_per_shot: float = RangedDamageFormula.LAUNCH_STAGGER
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
		var launch_delay: float = float(i) * stagger_per_shot
		var flight: float = _flight_for(hit, launch_delay)
		var proj := Projectile.new()
		proj.path = _resolved_path()
		proj.visual_scene = visual_scene
		proj.flight_time = flight
		proj.face_velocity = face_velocity
		add_child(proj)
		proj.tree_exiting.connect(func() -> void:
			pending[0] -= 1)
		proj.launch(
				hit.origin.global_position,
				hit.target.global_position,
				launch_delay)
		# Tint hook: Projectile.launch instantiates the visual synchronously
		# as its first child. Stamp tint right after so LightArrow reads the
		# attacker colour on first draw. Visuals without a `tint` field
		# ignore the assignment.
		if proj.get_child_count() > 0:
			var v: Node = proj.get_child(0)
			if "tint" in v:
				v.set("tint", tint)
		pending[0] += 1
		_show_presentation(hit, launch_delay + flight, pending)
	while pending[0] > 0:
		await get_tree().process_frame


## How long shot [param hit]'s arrow is in the air. [member
## DamageInstance.arrival_time] is the shot's FULL time to impact from volley
## start (#480 + stagger): [code]index * LAUNCH_STAGGER + distance /
## RangedDamageFormula.PROJECTILE_SPEED[/code], stamped by RangedAttackPlan.resolve.
## [param launch_delay] strips this shot's own launch offset back out, so the
## arrow flies for exactly its airtime and lands (and its reveal fires) at the
## recorded time — far shots visibly take longer than near ones, and a replay
## reconstructs the volley from recorded data alone.
##
## [b]This used to be two clocks and that was the bug.[/b] The arrow flew for a
## flat [member flight_time] while the reveal waited `arrival_time` from t=0,
## ignoring the per-shot stagger entirely — so HP dropped and the damage number
## popped while the arrow was still halfway there. `flight_time` is now the
## floor, not a parallel schedule: it keeps a point-blank shot from being an
## instant blink.
func _flight_for(hit: DamageInstance, launch_delay: float) -> float:
	if hit.arrival_time <= 0.0:
		return flight_time
	return maxf(hit.arrival_time - launch_delay, flight_time * MIN_FLIGHT_FRACTION)


## Fires the presentation-clock reveal (#479/#481) at [param impact_time] — the
## instant this shot's arrow actually reaches the target, launch stagger
## included. Pure observer: damage already landed synchronously in
## BattleSystem._apply_outcome (#474) before [method play] ever ran; this only
## tells presentation-only subscribers (HP bar, node tint, damage number, death
## VFX) that the shot arrived. Included in `pending` so [method play] doesn't
## return (and get torn down by [AttackVFX]) before this fires.
func _show_presentation(hit: DamageInstance, impact_time: float, pending: Array[int]) -> void:
	if impact_time > 0.0:
		await get_tree().create_timer(impact_time).timeout
	Events.damage_shown.emit(hit.target, hit.effective_amount)
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
