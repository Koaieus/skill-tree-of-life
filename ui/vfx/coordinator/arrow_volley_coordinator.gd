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

## #950 — landing-point spread. Margin off [member SkillNode.radius] (the
## GROWN radius) so nothing lands right on the rim, and the gaussian's sigma
## as a fraction of that margin — owner's number (`r_max / 2.5`), tunable
## here without touching the draw loop.
const _LANDING_MARGIN: float = 0.9
const _LANDING_SIGMA_FACTOR: float = 1.0 / 2.5

## #1042 — the parked spread at the leaf: a golden-angle spiral inside the
## leaf's inner disc, radius growing with the square root of the arrow's rank
## so the discs fill evenly (a sunflower), capped at this fraction of the
## node's radius so no arrow pokes out of the rim before it flies.
const _PARK_MARGIN: float = 0.6
const _GOLDEN_ANGLE: float = 2.399963
## Seconds one parked arrow takes to fade/scale in once its placement beat
## comes — the "fast" of the owner's "staggered animate in per arrow (but
## fast)"; the stagger itself is [member PresentationTempo.volley_place_stagger].
const _PLACE_IN: float = 0.08
const _PLACE_SCALE: float = 0.4
## How far under its authored glow a firing leaf starts the wind-up — a VALUE
## dimmer on the body's [member NodeVisualsComposite.feedback_tint] (the
## hit-flash channel, via [method SkillNode.node_visuals] — never the node's
## `modulate`, which would multiply the hover ring down, #304), the blade's
## [constant SkillBlade._FORM_DIM] pattern (`.claude/rules/hdr-color.md`): the
## leaf powers UP over the draw, its tiers are never re-picked.
const _LEAF_DIM: float = 0.45
## The tangent probe for a parked arrow's facing: the path's heading between
## `evaluate(0)` and `evaluate(ε)`.
const _TANGENT_EPS: float = 0.02

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

## The wind-up's parked arrows (#1042), in arrow-hit order, and the landing
## point each was aimed at when parked — the flight has to take off toward the
## point the arrow already faces, so the landing is drawn once, here, and
## [method play] launches to it rather than re-rolling.
var _parked: Array[Projectile] = []
var _parked_landings: PackedVector2Array = PackedVector2Array()
## Leaves dimmed for the wind-up, restored on exit so a cut-short wind-up
## never leaves a node under-lit.
var _dimmed_leaves: Array[SkillNode] = []
var _windup_tween: Tween = null


func _exit_tree() -> void:
	_restore_leaves()


## The presenter contract's marker — what the director should follow NOW, or
## null for nothing yet (#1048). Null through the draw: nothing moves while the
## arrows are parked, so a follow opened at commit would pin a static point.
## [method play] hands over the `%FocusMarker` [SwarmFocus] at first release
## and the target node at last release, each via [signal focus_marker_changed].
## Always null for a code-built coordinator with no marker.
func focus_marker() -> Node2D:
	return _handed_marker if is_instance_valid(_handed_marker) else null


func _hand_over(marker: Node2D) -> void:
	_handed_marker = marker
	focus_marker_changed.emit(marker)


var _handed_marker: Node2D = null


func _focus() -> SwarmFocus:
	return get_node_or_null(^"%FocusMarker") as SwarmFocus


## The ranged wind-up (#1042, ADR 0027): every arrow of the volley spawns NOW,
## parked at its firing leaf — spread inside the leaf's inner disc, facing its
## own path's t=0 tangent — animating in one by one on
## [member PresentationTempo.volley_place_stagger] while each firing leaf ramps
## from dimmed to its authored glow. Returns the draw time, which
## [BattleSystem._stage_windup] waits out before [method play] releases the
## parked set. The marker sits at the firing centroid throughout.
##
## Reads the hits off [member VFXCoordinator.outcome] (set at mount). With no
## outcome it falls back to the plan's own firing schedule — the playground's
## path, and a plan whose leaves the commit has already marked fired reports
## fewer shots there, which is why the outcome is the primary source.
##
## A draw time of 0.0 stages nothing at all: [method play] then spawns and
## launches exactly as before, frame for frame — the tempo escape hatch.
func begin_windup(plan: AttackPlan, tempo: PresentationTempo) -> float:
	_handed_marker = null
	var draw: float = maxf(0.0, tempo.volley_draw_time) if tempo != null else 0.0
	if draw <= 0.0:
		return 0.0
	_clear_parked()
	var shots := _shots(plan)
	if shots.is_empty():
		return 0.0
	var seed: int = outcome.resolve_seed if outcome != null \
			else (plan.resolve_seed if plan != null else 0)
	var stagger: float = maxf(0.0, tempo.volley_place_stagger)
	var tint := _resolve_tint(outcome.hits) if outcome != null else _resolve_tint([])
	var total := shots.size()
	# Per-leaf rank and count drive the spread, so two leaves each firing
	# three arrows get the same three-slot sunflower.
	var per_leaf: Dictionary = {}
	for shot in shots:
		per_leaf[shot.origin] = int(per_leaf.get(shot.origin, 0)) + 1
	var rank_in_leaf: Dictionary = {}
	var centroid := _centroid(per_leaf.keys())
	var target_pos: Vector2 = (shots[0].target as SkillNode).global_position
	_windup_tween = create_tween().set_parallel(true)
	for k in total:
		var shot: Dictionary = shots[k]
		var leaf: SkillNode = shot.origin
		var target: SkillNode = shot.target
		var rank: int = int(rank_in_leaf.get(leaf, 0))
		rank_in_leaf[leaf] = rank + 1
		var at: Vector2 = leaf.global_position + _park_offset(leaf, rank, int(per_leaf[leaf]))
		var landing: Vector2 = target.global_position + _landing_offset(seed, shot.index, target)
		var proj := _spawn_projectile(tint)
		var path: ProjectilePath = proj.path
		var tangent: Vector2 = path.evaluate(_TANGENT_EPS, at, landing) - path.evaluate(0.0, at, landing)
		proj.place(at, tangent.angle() if tangent.length_squared() > 1e-9 else (landing - at).angle())
		_parked.append(proj)
		_parked_landings.append(landing)
		# Animate in: alpha is the fade channel, scale the pop; delayed by
		# this arrow's placement beat.
		proj.modulate.a = 0.0
		proj.scale = Vector2.ONE * _PLACE_SCALE
		var place_at: float = float(k) * stagger
		_windup_tween.tween_property(proj, "modulate:a", 1.0, _PLACE_IN).set_delay(place_at)
		_windup_tween.tween_property(proj, "scale", Vector2.ONE, _PLACE_IN).set_delay(place_at)
		_windup_tween.tween_callback(Events.volley_arrow_placed.emit.bind(k, total)).set_delay(place_at)
	for leaf in per_leaf:
		_dim_leaf(leaf as SkillNode, draw)
	var focus := _focus()
	if focus != null:
		focus.begin_wave(centroid, target_pos)
	return draw


## The volley as `{origin, target, index}` per arrow — index is the hit's
## position in [member AttackOutcome.hits], the landing-offset seed key the
## no-wind-up path uses too, so a parked arrow lands where a fresh one would.
func _shots(plan: AttackPlan) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if outcome != null and not outcome.hits.is_empty():
		for i in outcome.hits.size():
			var hit: HitInstance = outcome.hits[i]
			if hit.origin == null or hit.target == null or hit is StatusInstance:
				continue
			out.append({origin = hit.origin, target = hit.target, index = i})
		return out
	var ranged := plan as RangedAttackPlan
	if ranged == null:
		return out
	var schedule := ranged.get_firing_schedule()
	for i in schedule.size():
		var shot: RangedAttackPlan.FiringShot = schedule[i]
		if shot.firing_node == null or shot.target == null:
			continue
		out.append({origin = shot.firing_node, target = shot.target, index = i})
	return out


## Where the [param rank]-th of [param count] arrows parks inside [param leaf]'s
## disc: a sunflower (golden-angle spiral, sqrt radius) so the slots spread
## evenly and never all from dead centre. Deterministic per leaf.
func _park_offset(leaf: SkillNode, rank: int, count: int) -> Vector2:
	var r_max: float = _PARK_MARGIN * leaf.radius
	if r_max <= 0.0 or count <= 1:
		return Vector2.ZERO
	var rho: float = r_max * sqrt((float(rank) + 0.5) / float(count))
	return Vector2.from_angle(float(rank) * _GOLDEN_ANGLE) * rho


## The firing-nodes centroid — per distinct leaf, not per arrow, so a leaf
## firing three arrows does not drag the marker toward itself.
func _centroid(leaves: Array) -> Vector2:
	var sum := Vector2.ZERO
	for leaf in leaves:
		sum += (leaf as SkillNode).global_position
	return sum / float(maxi(1, leaves.size()))


func _dim_leaf(leaf: SkillNode, draw: float) -> void:
	if leaf == null or not is_instance_valid(leaf):
		return
	var body: Node2D = leaf.node_visuals()
	if body == null:
		return
	_dimmed_leaves.append(leaf)
	body.feedback_tint = Color(_LEAF_DIM, _LEAF_DIM, _LEAF_DIM, 1.0)
	_windup_tween.tween_property(body, "feedback_tint", Color.WHITE, draw)


func _restore_leaves() -> void:
	for leaf in _dimmed_leaves:
		if is_instance_valid(leaf) and leaf.node_visuals() != null:
			leaf.node_visuals().feedback_tint = Color.WHITE
	_dimmed_leaves.clear()


func _clear_parked() -> void:
	for proj in _parked:
		if is_instance_valid(proj):
			proj.queue_free()
	_parked.clear()
	_parked_landings.clear()


func _spawn_projectile(tint: Color) -> Projectile:
	var proj := Projectile.new()
	proj.path = _resolved_path()
	proj.visual_scene = visual_scene
	proj.face_velocity = face_velocity
	add_child(proj)
	return proj


## Tint hook: the visual is instantiated synchronously as the projectile's
## first child (at `place` or `launch`). Stamp tint right after so LightArrow
## reads the attacker colour on first draw. Visuals without a `tint` field
## ignore the assignment.
func _stamp_tint(proj: Projectile, tint: Color) -> void:
	if proj.get_child_count() > 0:
		var v: Node = proj.get_child(0)
		if "tint" in v:
			v.set("tint", tint)


## Σ|amount| of the landing's hits — the arrow's own plus the typed status
## riding it (the [StatusInstance]s appended right after it, same target).
## Authored `amount`, never `effective_amount` (written at apply time).
func _focus_weight(hits: Array[HitInstance], i: int) -> float:
	var hit: HitInstance = hits[i]
	var weight: float = absf(hit.amount)
	var j := i + 1
	while j < hits.size() and hits[j] is StatusInstance and hits[j].target == hit.target:
		weight += absf(hits[j].amount)
		j += 1
	return maxf(weight, SwarmFocus.STATUS_FLOOR)


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
	#
	# The one thing skipped is skipped by CLASS, not kind: a typed arrow's
	# status (#495, `RangedStatusInstance`) is a second hit for the SAME
	# landing, sharing the arrow's origin and target — it never was an arrow,
	# so drawing it would land two arrows on one beat.
	var hits := outcome.hits
	if hits.is_empty():
		return
	if outcome.schedule == null:
		outcome.schedule = OutcomeSchedule.compile(outcome, tempo)
	var schedule: OutcomeSchedule = outcome.schedule
	var tint := _resolve_tint(hits)
	var pending: Array[int] = [hits.size()]
	# #1042 — the release. Parked arrows (a preceding `begin_windup`) launch
	# from where they sit toward the landing they were aimed at; without a
	# wind-up every arrow spawns and launches here, as it always did. The
	# release beat is ranked by `launch_at`, the landing cluster announced
	# once for the director's zoom, and the marker's wave opened.
	var arrow_indices: Array[int] = []
	for i in hits.size():
		var hit: HitInstance = hits[i]
		if hit.origin != null and hit.target != null and not hit is StatusInstance:
			arrow_indices.append(i)
	var total := arrow_indices.size()
	var release_rank: Dictionary = {}
	var by_launch := arrow_indices.duplicate()
	by_launch.sort_custom(func(a: int, b: int) -> bool:
		var ea: ScheduleEntry = schedule.entry_for(hits[a])
		var eb: ScheduleEntry = schedule.entry_for(hits[b])
		var la: float = ea.launch_at if ea != null else 0.0
		var lb: float = eb.launch_at if eb != null else 0.0
		return la < lb if la != lb else a < b)
	for r in by_launch.size():
		release_rank[by_launch[r]] = r
	var parked_count := _parked.size()
	if parked_count > total:
		for k in range(total, parked_count):
			if is_instance_valid(_parked[k]):
				_parked[k].queue_free()
	var landing_points := PackedVector2Array()
	var last_proj: Projectile = null
	var last_target: SkillNode = null
	var leaves: Dictionary = {}
	var arrow_k := 0
	for i in hits.size():
		var hit: HitInstance = hits[i]
		if hit.origin == null or hit.target == null or hit is StatusInstance:
			pending[0] -= 1
			continue
		var k := arrow_k
		arrow_k += 1
		# Read, not re-derived (#543). Both ends of the flight window are the
		# compiler's, so `launch_delay + flight == arrive_at` holds by
		# construction rather than by an algebraic argument about two exports
		# that were free to drift.
		var entry: ScheduleEntry = schedule.entry_for(hit)
		var launch_delay: float = maxf(0.0, entry.launch_at) if entry != null else 0.0
		var flight: float = _flight_for(entry)
		var parked: Projectile = _parked[k] if k < parked_count and is_instance_valid(_parked[k]) else null
		var proj: Projectile = parked if parked != null else _spawn_projectile(tint)
		proj.flight_time = flight
		proj.context = entry
		proj.focus_weight = _focus_weight(hits, i)
		proj.tree_exiting.connect(func() -> void:
			pending[0] -= 1)
		proj.released.connect(Events.volley_arrow_released.emit.bind(int(release_rank[i]), total))
		if int(release_rank[i]) == total - 1:
			last_proj = proj
			last_target = hit.target
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
		var origin: Vector2 = proj.global_position if parked != null else hit.origin.global_position
		var landing: Vector2 = _parked_landings[k] if parked != null \
				else hit.target.global_position + _landing_offset(outcome.resolve_seed, i, hit.target)
		proj.launch(origin, landing, launch_delay)
		_stamp_tint(proj, tint)
		landing_points.append(landing)
		leaves[hit.origin] = true
	_parked.clear()
	_parked_landings.clear()
	if total > 0:
		var focus := _focus()
		if focus != null:
			focus.begin_wave(_centroid(leaves.keys()), hits[arrow_indices[0]].target.global_position)
			# First release: something moves now, so the follow opens here.
			_hand_over(focus)
	if last_proj != null:
		# The LAST launch is the landing beat (#1048): the frame is empty of
		# parked arrows and the volley is about to arrive — tighten onto the
		# target and follow it. Off this coordinator's own loop, not the global
		# bus. Bound after the loop: the packed array is copied at bind time.
		last_proj.released.connect(_on_last_release.bind(landing_points, last_target),
				CONNECT_ONE_SHOT)
	while pending[0] > 0:
		await get_tree().process_frame
	_restore_leaves()


## The volley's last arrow left the string: announce the landing cluster for
## the director's tighten and hand the target over as the thing to follow.
func _on_last_release(landing_points: PackedVector2Array, target: SkillNode) -> void:
	wave_landing.emit(landing_points)
	if target != null and is_instance_valid(target):
		_hand_over(target)


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
##
## The same read picks the ABSORB beat, `_on_absorbed(gained)`, for a landing
## that went through mitigation and changed nothing hostile: `gained = true`
## when it flipped to [constant HitInstance.Kind.HEAL] (the shot fed the
## defender), `false` when it mitigated to exactly zero (the armour held).
## The gate is checked first: a gated hit never reached mitigation, and its
## `effective_amount` is 0.0 by construction, so it must never read as "held".
## Only the impact beat differs — the flight never anticipates the outcome.
func _on_arrow_arrived(proj: Projectile, hit: HitInstance) -> void:
	if proj.get_child_count() == 0:
		return
	var v: Node = proj.get_child(0)
	if hit.gated:
		if v.has_method(&"_on_dud"):
			v.call(&"_on_dud")
		return
	var healed := hit.kind == HitInstance.Kind.HEAL
	var held := hit.kind == HitInstance.Kind.DAMAGE and is_zero_approx(hit.effective_amount)
	if (healed or held) and v.has_method(&"_on_absorbed"):
		v.call(&"_on_absorbed", healed)


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


## #950 — where THIS arrow lands on the target's disc, purely cosmetic:
## flight path and impact VFX aim here, but the hit, the damage and the land
## beat all still resolve against [param target]'s true centre untouched.
##
## Gaussian radius clamped into `[0, r_max]`, uniform angle — the owner's
## spec verbatim (2026-09-18). Seeded off the outcome's own
## [member AttackOutcome.resolve_seed] ([param seed]) plus this shot's index,
## never the gameplay RNG (`.claude/rules/multiplayer-sync.md`): a mirror
## replaying the same [AttackRecord] draws the identical spread, since both
## ends see the same seed and the same hit order.
func _landing_offset(seed: int, index: int, target: SkillNode) -> Vector2:
	var r_max: float = _LANDING_MARGIN * target.radius
	if r_max <= 0.0:
		return Vector2.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%d" % [seed, index])
	var sigma: float = r_max * _LANDING_SIGMA_FACTOR
	var rho: float = clampf(absf(rng.randfn(0.0, sigma)), 0.0, r_max)
	var phi: float = rng.randf_range(0.0, TAU)
	return Vector2.from_angle(phi) * rho
