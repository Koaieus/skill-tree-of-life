@tool
class_name ArrowVolleyCoordinator
extends VFXCoordinator

## Ranged-attack volley: one [Projectile] per entry of
## [member AttackOutcome.hits] — literally every one, per scheduled shot —
## all converging on the same target. Each shot's
## launch is staggered by RangedAttackPlan's authored ramp — recovered here
## from the shot's own [ScheduleEntry] window, not a
## per-index constant — so a wide volley reads as a flurry of arrival
## impacts rather than one monolithic THWACK. (The ramp is metric, so leaves
## at the SAME distance genuinely do fire together; a perfectly symmetric
## firing ring collapses back to one THWACK by construction.)
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
## attacker's [member Entity.color], read off [member HitInstance.attacker]
## (promoted to the base class in #507; the record round-trip drops
## [member HitInstance.source], so tint must never read it).
##
## [b]Every scheduled shot flies and arrives, whatever it did[/b] — there is no
## filter on outcome here, by owner call (see [method play]). A shot the
## land-time gate vetoes (#503, target overkilled mid-volley) lands INERT, and
## a shot that mitigated to zero or flipped to a heal still draws its arrow:
## see [method _on_arrow_arrived].

const _DEFAULT_VISUAL: PackedScene = preload("res://ui/vfx/projectile/visual/light_arrow.tscn")

@export var projectile_path: ProjectilePath
@export var visual_scene: PackedScene = _DEFAULT_VISUAL

## Fallback airtime, used ONLY for a shot whose [ScheduleEntry] reports a
## zero-length window (a hand-built outcome with no ramp). A scheduled shot
## flies for exactly [method ScheduleEntry.window] and this is not consulted.
@export var flight_time: float = 0.45
## Fallback SHAPE for an outcome that arrives with no compiled
## [member AttackOutcome.schedule]. On the real path [RangedAttackPlan] already
## compiled one at resolve, so this is never consulted; null falls back to
## [method PresentationTempo.shared_default].
##
## Replaces the old `shot_flight_time` export, which existed solely to
## re-derive a launch delay this coordinator now simply reads (#543 D3).
@export var tempo: PresentationTempo = null
@export var face_velocity: bool = true


func play(payload: Variant) -> void:
	var outcome := payload as AttackOutcome
	if outcome == null:
		return
	# EVERY landing gets an arrow — no filter on `kind`, deliberately.
	# Owner call 2026-09-04: "each arrow should fire, regardless of what they
	# do. render. every. arrow. damage? render. 0? render. heal? render."
	#
	# This used to read `outcome.damage_hits()`, which keeps only
	# [constant HitInstance.Kind.DAMAGE]. That silently deleted the whole
	# volley whenever mitigation flipped its hits to HEAL — a shot into a
	# node whose net `min_damage_taken` is negative (bunker_addon authors
	# `-5`) mitigates to a negative number, which [method NodeCombat.take_damage]
	# reclassifies as a heal by design. The player spent the AP and saw
	# nothing leave the bow.
	var hits := outcome.hits
	if hits.is_empty():
		return
	if outcome.schedule == null:
		outcome.schedule = OutcomeSchedule.compile(outcome, tempo)
	var schedule: OutcomeSchedule = outcome.schedule
	var tint := _resolve_tint(hits)
	var pending: Array[int] = [hits.size()]
	for i in hits.size():
		var hit: HitInstance = hits[i]
		if hit.origin == null or hit.target == null:
			pending[0] -= 1
			continue
		# Read, not re-derived (#543). Both ends of the flight window are the
		# compiler's, so `launch_delay + flight == arrive_at` holds by
		# construction rather than by an algebraic argument about two exports
		# that were free to drift.
		var entry: ScheduleEntry = schedule.entry_for(hit)
		var launch_delay: float = maxf(0.0, entry.launch_at) if entry != null else 0.0
		var flight: float = _flight_for(entry)
		var proj := Projectile.new()
		proj.path = _resolved_path()
		proj.visual_scene = visual_scene
		proj.flight_time = flight
		proj.face_velocity = face_velocity
		proj.context = entry
		add_child(proj)
		proj.tree_exiting.connect(func() -> void:
			pending[0] -= 1)
		# #503: the arrow flies on ITS OWN clock (this coordinator is a pure
		# observer, #474/#504) while OutcomeApplier decides the gate on ITS
		# OWN clock — both converging on the schedule's `arrive_at`, never coupled
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
func _on_arrow_arrived(proj: Projectile, hit: HitInstance) -> void:
	if not hit.gated or proj.get_child_count() == 0:
		return
	var v: Node = proj.get_child(0)
	if v.has_method(&"_on_dud"):
		v.call(&"_on_dud")


## How long shot [param entry]'s arrow is in the air —
## [method ScheduleEntry.window], i.e. `arrive_at - launch_at`, both assigned
## by [method OutcomeSchedule.compile] from the volley's authored
## [member PresentationTempo.volley_flight_time].
##
## [b]This used to be two clocks and that was the bug.[/b] The arrow flew for a
## flat [member flight_time] while the reveal waited `arrival_time` from t=0,
## ignoring the per-shot stagger entirely — so HP dropped and the damage number
## popped while the arrow was still halfway there. The fix was to recover the
## launch delay by subtracting a SECOND export that had to stay equal to a
## resolver constant; #543 deleted that handshake by making the compiler own
## both ends of the window, so there is nothing left to keep in step.
##
## [b]There is deliberately no floor here.[/b] A `MIN_FLIGHT_FRACTION` clamp
## used to guard against a point-blank shot blinking instantly; under the
## constant-flight-time schedule that case cannot arise — the nearest leaf gets
## a full airtime just like the furthest, so the floor was a floor under a
## constant. The fallback below fires only for an entry that does not exist or
## reports no window at all, never to paper over a mistuned number.
func _flight_for(entry: ScheduleEntry) -> float:
	if entry == null or entry.window() <= 0.0:
		return flight_time
	return entry.window()


# Resolve attacker tint off [member HitInstance.attacker] — a typed
# base-class field since #507. This used to duck-type through
# `hit.source.attacker`, which only worked because a ranged hit's `source`
# happened to be its [RangedAttackPlan]; #511 dropped `source` from the wire
# (it is a Variant of resolve-local residue, and this was its one real
# reader), so a replayed volley has none. Falls back to the LightArrow
# default when no hit names an attacker.
func _resolve_tint(hits: Array[HitInstance]) -> Color:
	for hit in hits:
		if hit.attacker != null:
			return hit.attacker.color
	return Color(1.0, 0.9, 0.6, 1.0)


func _resolved_path() -> ProjectilePath:
	if projectile_path != null:
		return projectile_path
	return BezierArcPath.new()
