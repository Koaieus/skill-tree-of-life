@tool
class_name ArrowVolleyCoordinator
extends VFXCoordinator

## Ranged-attack volley: one [Projectile] per [member AttackOutcome.hits]
## (i.e. per scheduled shot), all converging on the same target. Each shot's
## launch is staggered by RangedAttackPlan's authored ramp — recovered here
## from the shot's own recorded [member DamageInstance.arrival_time], not a
## per-index constant — so a wide volley reads as a flurry of arrival
## impacts rather than one monolithic THWACK.
##
## Pure observer (#474/#504) — this coordinator never calls take_damage; it
## only renders. Note it now runs CONCURRENTLY with the mutation loop rather
## than after it: [BattleSystem] starts [method play] un-awaited and
## [OutcomeApplier] lands each hit at that hit's own `arrival_time`, so the
## arrow is genuinely in flight while its damage is still pending. That is the
## whole point — the HP bar, shatter, fog and damage number all move as the
## arrow strikes, because they are all reading the model. Observer status is
## unchanged: the applier waits on its own timer, never on this animation, so
## dropping every frame here leaves the applied world identical.
##
## Uses the [LightArrow] visual by default — oriented glowing arrow that
## sticks into the target node and fades. Arrows are tinted by the
## attacker's [member Entity.color], read off [member DamageInstance.source]
## (a [RangedAttackPlan], which carries [code]attacker[/code]).
##
## Every scheduled shot still flies and arrives — a shot the land-time gate
## vetoes (#503, target overkilled mid-volley) is not skipped, it lands
## INERT: see [method _on_arrow_arrived].

const _DEFAULT_VISUAL: PackedScene = preload("res://ui/vfx/projectile/visual/light_arrow.tscn")

@export var projectile_path: ProjectilePath
@export var visual_scene: PackedScene = _DEFAULT_VISUAL
## Floor on a shot's airtime, as a fraction of [member flight_time] — a
## point-blank shot still needs enough frames to read as an arrow.
const MIN_FLIGHT_FRACTION: float = 0.4

## Fallback airtime for a shot with no [member DamageInstance.arrival_time],
## and (scaled by [constant MIN_FLIGHT_FRACTION]) the floor for one that has.
@export var flight_time: float = 0.45
## The per-shot flight duration RangedAttackPlan.resolve() baked into every
## `arrival_time` (`launch_time + shot_flight_time`). Defaults to the domain
## constant so VFX and the recorded timeline share one source of truth;
## overriding it only retempos how launch_delay is recovered from
## arrival_time, not the reveal itself (that still rides the recorded
## [member DamageInstance.arrival_time]).
@export var shot_flight_time: float = RangedDamageFormula.FLIGHT_TIME
@export var face_velocity: bool = true


func play(payload: Variant) -> void:
	var outcome := payload as AttackOutcome
	if outcome == null:
		return
	# Ranged never produces genuine heals, but `outcome.hits` is
	# `Array[HitInstance]` (#381) — filter to damage explicitly rather than
	# relying on every entry being a DamageInstance.
	var hits := outcome.damage_hits()
	if hits.is_empty():
		return
	var tint := _resolve_tint(hits)
	var pending: Array[int] = [hits.size()]
	for i in hits.size():
		var hit: DamageInstance = hits[i]
		if hit.origin == null or hit.target == null:
			pending[0] -= 1
			continue
		var launch_delay: float = maxf(hit.arrival_time - shot_flight_time, 0.0)
		var flight: float = _flight_for(hit, launch_delay)
		var proj := Projectile.new()
		proj.path = _resolved_path()
		proj.visual_scene = visual_scene
		proj.flight_time = flight
		proj.face_velocity = face_velocity
		add_child(proj)
		proj.tree_exiting.connect(func() -> void:
			pending[0] -= 1)
		# #503: the arrow flies on ITS OWN clock (this coordinator is a pure
		# observer, #474/#504) while OutcomeApplier decides the gate on ITS
		# OWN clock — both converging on `hit.arrival_time`, never coupled
		# directly. `arrived` fires at THIS arrow's own touchdown; by
		# construction that lands at/around the same beat the applier lands
		# (or vetoes) `hit`, so reading `hit.gated` there is reading the
		# model at the moment its own visual needs the answer — same
		# discipline as the tint read below, never a second gate computed
		# independently.
		proj.arrived.connect(_on_arrow_arrived.bind(proj, hit))
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
	while pending[0] > 0:
		await get_tree().process_frame


## #503 — the dud beat. [param hit] is the SAME [HitInstance] instance
## [OutcomeApplier] just landed (or vetoed): [member HitInstance.gated] is
## the model telling this arrow how it actually resolved, read at the arrow's
## own arrival rather than predicted at launch (the gate can only be known
## once the model re-checks it live, per docs/domain/attack-timeline.md).
##
## A live hit needs nothing here — [member _resolve_tint]'s launch-time stamp
## already stands. A gated one desaturates: no damage number follows (the
## applier never called `take_damage`, so `Events.skill_node_damaged` never
## fires for it), so the arrow itself has to carry "this overkilled" alone.
## Named-tier only, per `.claude/rules/hdr-color.md` — never a hand-picked
## float. [constant Emissive.INERT] is exactly the "visible, never blooms"
## reading the issue calls for.
##
## `_on_dud()` is part of the duck-typed visual contract, alongside
## `_on_launch()` / `_on_progress(t)` / `_on_arrival()` — the visual owns what
## a dud looks like, because only it knows which tiers its own `_draw` already
## applies. [LightArrow] desaturates and drops to [constant Emissive.INERT].
## A visual that doesn't implement the hook simply renders no dud; the
## coordinator does NOT reach in and retint it, which would couple this file
## to that visual's internal emissive choices.
func _on_arrow_arrived(proj: Projectile, hit: DamageInstance) -> void:
	if not hit.gated or proj.get_child_count() == 0:
		return
	var v: Node = proj.get_child(0)
	if v.has_method(&"_on_dud"):
		v.call(&"_on_dud")


## How long shot [param hit]'s arrow is in the air. [member
## DamageInstance.arrival_time] is the shot's FULL time to impact from volley
## start: [code]DRAW_TIME + lerp(0, TOTAL_STAGGER, rank / (n - 1)) +
## RangedDamageFormula.FLIGHT_TIME[/code], stamped by RangedAttackPlan.resolve
## from the rank-authored ramp (docs/domain/attack-timeline.md "The ranged
## volley ramp"). [param launch_delay] strips this shot's own launch offset
## back out, so the arrow flies for exactly its airtime and lands (and its
## reveal fires) at the
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


# Resolve attacker tint: the RangedAttackPlan is the hit source and
# carries `attacker: Entity` with a `color`. Defensive — any non-conforming
# source falls back to the LightArrow default.
func _resolve_tint(hits: Array[DamageInstance]) -> Color:
	for hit in hits:
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
