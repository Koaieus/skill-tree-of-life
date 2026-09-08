class_name BladeSwingClock
extends RefCounted

## The swing's own clock, and the channel Fortification's drag acts on (#780).
##
## [b]Drag slows the CLOCK, never a particle.[/b] Subtracting velocity from a
## particle on a rigid blade does nothing: the distance constraints fight it,
## and then [method BladeSim._step] re-applies the drivers AFTER the Verlet
## integration, so [method BladeArcDriver.apply] — a pure function of its
## argument — overwrites the damped position outright. Particle-level damping
## therefore has no effect on exactly the rigid blade it is meant to slow.
## (That is also why [member BladeSim.simulate]'s `linear_damping` is the wrong
## channel: it is the free-flight knob for an UNPINNED fragment, where there is
## no driver to overwrite anything.) What drag can move is the argument itself —
## the angular progress `f` the arc driver evaluates its ease curve at.
##
## [b]Where this sits under ADR 0005.[/b] A spike destroys matter, a bunker
## destroys structure, and a wall destroys neither — it spends the swing's
## budget instead. Drag removes no blade part, so it is a THIRD defensive
## effect that cannot violate the ADR's vertex/edge disjointness rather than an
## exception to it. Sensing on capsules as well as discs (below) is a question
## of what the swing TOUCHES, not of which blade part is doing the defending, so
## it does not disturb that either.
##
## [b]Monotonic by construction.[/b] [member _f] only ever has a non-negative
## quantity added and is clamped at 1: the warp factor [method warp] is
## `1 / (1 + drag)` with `drag >= 0`, hence strictly positive and at most 1. No
## configuration of fortified nodes can reverse a swing, and none can freeze one
## either — the hard stall is #781's bunker, not this. What a wall does instead
## is spend the arc: five nodes at drag 1 leave the swing running at a sixth of
## its nominal rate, so within the fixed swing duration it covers roughly a
## sixth of its sweep and everything further round the arc is simply never
## reached. That is how a wall protects what is behind it without deleting,
## severing or cascading anything.
##
## [b]Causal, not global.[/b] A zone's drag is added only once its own contact
## has happened, so it slows the REST of the arc and never the approach to
## itself. A global warp would be paradoxical: a fortified node at the end of
## the sweep would retroactively prevent the swing from ever reaching it.
##
## [b]Two sensing models, deliberately (see docs/domain/melee-blade-sim.md).[/b]
## This class senses contact ANALYTICALLY — point-in-disc and
## point-to-segment — where [BladeHitScan] senses it through
## `PhysicsDirectSpaceState2D`. That is by necessity, not by preference:
## [AiBladeRollout] runs [method BladeSim.simulate] from `WorkerThreadPool`
## tasks, where a physics-server query is not safe, so the solver must never
## touch the space state. The consequence to know: at the margin a node can
## drag the swing without producing a hit EVENT, or produce one without having
## dragged. [BladeHitScan] remains the sole authority for hit events, damage and
## pops; this class decides only how fast the clock runs.

## Half-thickness of a blade edge. [b]Shared with [BladeHitScan], not copied.[/b]
## The two sensing MODELS are separate by necessity (see the class docstring),
## but the geometry they sense is one geometry: if the scan's capsules get
## thicker and drag's do not, a node starts draining without dragging and the
## divergence is invisible — the models are already allowed to disagree at the
## margin, so nothing would flag it. One const cannot drift; a comment saying
## "keep them equal" can.
const _EDGE_RADIUS := BladeHitScan.EDGE_RADIUS

## Drag zones — one per fortified defender node, parallel arrays. Positions are
## world-space, exactly like [member BladeState.positions].
var zone_centers: PackedVector2Array = PackedVector2Array()
var zone_radii: PackedFloat32Array = PackedFloat32Array()
var zone_drags: PackedFloat32Array = PackedFloat32Array()

## Nominal swing duration — the same value the drivers were built with.
var duration: float = 1.2

## Accumulated drag from every zone touched so far. Never decreases.
var drag: float = 0.0

## Zone indices already counted. A zone contributes its drag AT MOST ONCE for
## the whole swing — never disc + capsule, never once per incident edge.
var touched: Dictionary = {}

## Warped angular progress. Meaningful only once [member _warping] is true; see
## [method progress] for why it does not exist before that.
var _f: float = 0.0

## False until the first contact. [b]This is load-bearing, not an
## optimisation.[/b] Accumulating `f` in float steps from t=0 would drift from
## `t / duration` in the last bits, so a swing that merely has a fortified node
## in its FIELD — but never touches it — would produce a different trajectory
## from one that has none at all. Acceptance 5 ("drag has no effect on a blade
## that never contacts a fortified node") is a bit-exactness claim, and this
## flag is what makes it one: before first contact [method progress] declines to
## answer and the driver evaluates its original `t / duration` expression,
## unchanged, character for character.
var _warping: bool = false

## The most recent `t` a driver asked about, kept so the accumulator can be
## seeded from the exact pre-contact progress at the moment drag first lands.
var _last_t: float = 0.0


func _init(duration_: float = 1.2) -> void:
	duration = duration_


## Register one fortified defender node as a drag zone. `radius` is the node's
## own collision radius; `amount` its `swing_drag`.
func add_zone(center: Vector2, radius: float, amount: float) -> void:
	if amount <= 0.0:
		return
	zone_centers.append(center)
	zone_radii.append(radius)
	zone_drags.append(amount)


func has_zones() -> bool:
	return not zone_drags.is_empty()


## True once at least one zone has been touched — i.e. once this clock is
## actually diverging from nominal time.
func is_warping() -> bool:
	return _warping


## Time-warp factor in (0, 1]: the fraction of nominal angular rate the swing
## still advances at. Strictly positive for every `drag >= 0`, which is what
## makes progress non-decreasing AND keeps a hard stall out of this issue.
func warp() -> float:
	return 1.0 / (1.0 + drag)


## Open one substep at nominal time [param t]: remember it, and — once the
## clock is warping — advance the warped progress by this substep's share.
## Called by [method BladeSim._step] BEFORE the drivers apply, so a driver
## reading [method progress] on the same substep sees the advanced value.
##
## Monotonic: `sub_dt` and [method warp] are both positive, so `_f` only ever
## rises, and `minf` caps it at a completed sweep.
func tick(t: float, sub_dt: float) -> void:
	_last_t = t
	if not _warping or duration <= 0.0:
		return
	_f = minf(1.0, _f + (sub_dt / duration) * warp())


## The angular progress the arc driver should use, or -1.0 meaning "I have
## nothing to say — use your own `t / duration`". See [member _warping].
func progress() -> float:
	return _f if _warping else -1.0


## Test the blade's current pose against every untouched zone and bank the drag
## of each one it overlaps.
##
## Called once per TRAJECTORY SAMPLE, not once per substep: a sample is 1/120 s
## against a 1.2 s swing, so the granularity costs under 1% of the arc, and
## paying it per substep would quadruple a cost that is already the only
## per-step work the solver does outside its own constraint sweeps.
##
## [b]Discs AND rim-trimmed capsules[/b] (#785's Decisions: "a capsule contact
## is a full contact for every defender effect — damage, spikes, fortification
## drag and the bunker break"). Vertex-only sensing would be a head-on-ram
## model, which is the bunker's case; a SWEEP is the opposite — its edges cross
## exactly the gaps between the vertex arcs, so sensing discs alone would
## reintroduce spacing luck for drag MAGNITUDE against a wall. Spacing luck was
## ruled harmless for spikes because threading one spiked node is not a
## strategy; a wall is precisely the case where it would be, and the density
## gradient is the whole point of this mechanic.
##
## The capsule is trimmed back to each endpoint's disc rim exactly as
## [BladeHitScan] trims it, so a hub does not count once per incident edge —
## though `touched` would have caught that anyway.
func sense(
		positions: PackedVector2Array,
		radii: PackedFloat32Array,
		edges: Array[Vector2i],
		removed_edges: Dictionary) -> void:
	if zone_drags.is_empty() or touched.size() == zone_drags.size():
		return
	for z in zone_drags.size():
		if touched.has(z):
			continue
		if not _zone_overlaps(z, positions, radii, edges, removed_edges):
			continue
		touched[z] = true
		drag += zone_drags[z]
		if not _warping:
			# Seed the accumulator from the progress the drivers have been
			# reading nominally up to now, then take over from here. The zone's
			# own drag applies to the REST of the arc, never to the approach.
			_warping = true
			_f = clampf(_last_t / duration, 0.0, 1.0) if duration > 0.0 else 0.0


## True if zone [param z] overlaps any blade disc or any rim-trimmed edge
## capsule at this pose.
func _zone_overlaps(
		z: int,
		positions: PackedVector2Array,
		radii: PackedFloat32Array,
		edges: Array[Vector2i],
		removed_edges: Dictionary) -> bool:
	var c := zone_centers[z]
	var zr := zone_radii[z]
	for i in positions.size():
		var reach := zr + (radii[i] if i < radii.size() else 0.0)
		if c.distance_squared_to(positions[i]) <= reach * reach:
			return true
	var cap_reach := zr + _EDGE_RADIUS
	var cap_reach_sq := cap_reach * cap_reach
	for e_idx in edges.size():
		if removed_edges.has(e_idx):
			continue  # severed (#781) — a gone edge touches nothing
		var e := edges[e_idx]
		var a := positions[e.x]
		var b := positions[e.y]
		var delta := b - a
		var length := delta.length()
		if length <= 0.0:
			continue
		var ra := radii[e.x] if e.x < radii.size() else 0.0
		var rb := radii[e.y] if e.y < radii.size() else 0.0
		var trimmed := length - ra - rb
		if trimmed < 1e-4:
			continue  # discs already overlap; no exposed span (mirrors BladeHitScan)
		var dir := delta / length
		var p0 := a + dir * ra
		var p1 := p0 + dir * trimmed
		if _point_segment_distance_squared(c, p0, p1) <= cap_reach_sq:
			return true
	return false


## Squared distance from [param p] to segment [param a]-[param b] — the clamped
## projection, no transcendentals, no allocation.
static func _point_segment_distance_squared(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq <= 0.0:
		return p.distance_squared_to(a)
	var u := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_squared_to(a + ab * u)
