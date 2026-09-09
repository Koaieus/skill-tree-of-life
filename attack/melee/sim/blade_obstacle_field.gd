class_name BladeObstacleField
extends BladeConstraint

## Bunker deflection (#781): the solid obstacles a swing cannot pass through,
## and the strain meter that breaks a blade too rigid to go around them.
##
## [b]Since #811 this is THE defender field — both kinds.[/b] It wraps one
## immutable [BladeDefenderZones] (the physics query's result) and is the only
## thing in the solver that tests the blade against a defender. Two zone kinds,
## asymmetric on purpose:
##
## - a [b]plate[/b] (`deflection`, a BOOL stat — presence only, §805; only
##   [BunkerAddon] authors it) is pushed out of, meters strain, arms a break and
##   can stall the grip;
## - a [b]wall[/b] (`swing_drag`, a magnitude; [FortificationAddon]) is SENSED
##   and nothing more — [method project] skips it in the pushout and banks its
##   drag on the [BladeSwingClock] instead. A wall spends the swing's budget; it
##   does not stop the blade, and it must never shatter one. That is why a wall
##   never enters [member _near], which is not a neutral "was sensed" set: it
##   gates the strain accumulator that arms breaks and stalls grips, both of
##   which are plate-only effects (ADR 0005, #781).
##
## A node carrying both stats is ONE zone that is both kinds, latched once.
##
## [b]One object per swing, or none.[/b] [method MeleeAttackPlan.build_blade_state]
## attaches one to [member BladeState.obstacles] only when some defender of
## either kind is inside the swing's whip bound.
## A map with no defender therefore has NO field — no accumulator exists to be
## measured, nothing is allocated, and the solver runs the plain native path.
## That is the owner's false-positive guard, structurally: the strain metric is
## never "did this vertex move?" in general, it is only ever "how much of the
## drive this bunker's pushout refused" — and without a bunker there is nothing
## to refuse. [b]The native backend is off for any swing that HAS a field[/b]
## ([method BladeSim.simulate_range] gates on `clock == null and obstacles ==
## null`), so merging the two zone sets means more swings take the GDScript
## path than before — accepted under #811, tracked separately as #813.
##
## [b]Pushout.[/b] Projected every solver iteration AFTER the distance
## constraints (see [method BladeSim._step]), so the pass ends with every vertex
## disc and every rim-trimmed edge capsule pushed out of every bunker disc, to
## within [constant CONTACT_SLOP]. Discs are the same geometry [BladeHitScan]
## queries and [BladeSwingClock] senses; the capsule trim is theirs too.
##
## [b]Strain is the driver's residual.[/b] Each substep the arc drivers place
## the grip particles where the swing SHOULD be, and the projection pass then
## moves them to where the blade CAN be. For a floppy blade a bunker contact is
## absorbed by a fold — the grip keeps up with its driver and the unresolved
## advance is ~0. For a rigid blade no fold exists: the whole body rotates back
## against the driver, so the grip ends each substep roughly where it started
## and the unresolved advance is the full `speed * dt`. Summed over a contact,
## clamped at >= 0 (a step where the blade catches up SUBTRACTS — the bleed that
## washes out a transient hold), that is literally "how far the swing tried to
## drive the blade into the plate and could not", in world units. Crossing
## [constant SHATTER_DISTANCE] arms a break. This needs no rigidity
## computation: whether the blade yielded IS the rigidity measurement.
##
## Why not the contact vertex's own unresolved pushout (the issue's first
## formulation)? Driven particles are not pinned during the projection pass
## (only the pivot has `inv_mass 0`), so a rigid blade resolves the pushout
## COMPLETELY — by rotating back as a whole — and the contact point reads
## "fully resolved" in exactly the case that should shatter. Measured 2026-09-09
## on a clamped spine and a truss; see the issue thread.
##
## [b]What breaks is an EDGE, never a vertex[/b] — ADR 0005. The contact is
## usually at a vertex (discs stick out past the trimmed capsules); the edge
## that fails is the incident one that carried the most LOAD over the contact:
## each substep's unresolved drive is banked on every incident live edge in
## proportion to how squarely the plate's push runs along it (`|n . dir|`), and
## the biggest bank breaks, ties to the lowest index. (The ADR names the
## distance-constraint residual as the strain; in this solver that residual is
## ~0 after the pass — measured — because the body yields as a whole, so the
## load share is the same idea read off the push direction instead.) For a
## capsule contact it is that edge, at full share. Breaking is recorded as a PENDING request
## and applied by the resolve loop through [method BladePopResolver.LiveGate._sever_edge],
## the same path a spike pop takes (#801); this class never mutates
## `state.constraints`, so an optimistic bake stays a pure function the loop can
## rewind. Self-limiting by construction: once the edge is gone that region is
## floppy, the next contact yields, and the blade flows past.
##
## [b]The grip is a hard stall, not a break.[/b] A contact on a DRIVEN particle
## (a pivot neighbour) calls [method BladeSwingClock.stall]: the swing's clock
## freezes, the grip sits on the plate, nothing breaks, and everything outboard
## keeps simulating on its own momentum. Owner, 2026-09-07: a hard stall is less
## punishing than a shatter, and it dissolves the "pick the handle right next to
## the enemy bunker" exploit by making it self-punishing.
##
## [b]Sim state.[/b] The accumulators, the driver history and the pending break
## are captured by [method capture] / restored by [method restore] exactly like
## [BladeSwingClock.Bank], so the resolve loop's head replay lands bit-identically.
##
## [b]No pop budget on the bunker[/b] — deliberately unlike [SpikeRingAddon]'s
## `spikes` pool (#778). Spikes are dual-use (offensive `blade_damage` and
## defensive stopping power), so their defensive half is metered. A bunker is
## purely defensive and it is not immortal: every break still lands the
## contacting vertex's mitigated hit, so `node_health` IS the budget, and a
## second pool would charge the same node twice for the same job. Owner,
## 2026-09-08. If HP ever proves too coarse a meter, a dedicated
## `plate_integrity` pool (the owner's "tegridy") is the coherent next option —
## a hint, not a plan; nothing here anticipates it.
##
## [b]Analytic, allocation-free per substep, no physics-server calls: safe from
## [AiBladeRollout]'s worker threads.[/b] The physics IS what found the zones —
## one [method PhysicsDirectSpaceState2D.intersect_shape] per pivot, on the main
## thread — but by the time the solver sees them they are plain arrays on a
## shared, immutable [BladeDefenderZones]. Everything mutable lives on THIS
## object, one per swing, so a pivot's whole rollout can share one zone set
## without racing.

## How far a vertex disc may sink into a bunker disc before the pushout acts, in
## px. Not zero on purpose: [BladeHitScan] has to SEE the contact so the
## mitigated hit lands ("the hit still lands" is this issue's asymmetry with a
## spike pop), and two exactly-tangent circles are not a reliable overlap for a
## physics query. Also what keeps a resting contact from jittering. Edge capsules
## get no slop — an edge deals no damage, so nothing needs to see it touch.
const CONTACT_SLOP: float = 1.0

## The shatter threshold, in world px: how far the swing may try to drive a
## blade into a plate — unresolved, see the class docstring — before an edge
## breaks. Owner-tunable. It doubles as the visual penetration budget: the
## pushout runs every iteration regardless, so a vertex can never sit deeper
## than [constant CONTACT_SLOP] plus one substep's travel, well under this.
##
## [b]Pinned against the solver configuration[/b] — `BladeSim.DEFAULT_ITERATIONS`
## (16) split over `DEFAULT_SUBSTEPS` (4), the length axis on. More sweeps make
## a floppy blade resolve a contact MORE completely (its accumulator falls
## toward 0) and leave a rigid one exactly as stalled, so raising fidelity
## sharpens the separation rather than shifting the verdict — bounded, not
## eliminated. Re-read the classification test if that configuration changes.
const SHATTER_DISTANCE: float = 8.0

## A contact is considered ONGOING while any blade part is within this many px
## of a plate's surface, even on a substep the pushout had nothing to correct —
## a jammed blade jitters in and out of the slop band every substep, and
## resetting on each gap would never let the strain add up. Only once nothing
## is within the band does the zone's accumulator reset.
const CONTACT_HYSTERESIS: float = 4.0

## Shared with [BladeHitScan] and [BladeSwingClock], not copied — one geometry.
const _EDGE_RADIUS := BladeHitScan.EDGE_RADIUS


## One armed break, handed to the resolve loop by [method consume_break].
class Break extends RefCounted:
	var edge_idx: int
	## The GLOBAL sample step (see [method BladeSim.simulate_range]) whose
	## substeps armed it — the sample the loop severs at.
	var step: int
	var defender: SkillNode


## The mutable half of the field, for the resolve loop's rewind (#801).
class Bank extends RefCounted:
	var strain: PackedFloat32Array
	var edge_residual: Array[Dictionary]
	var driven_last: PackedVector2Array
	var driven_last_target: PackedVector2Array
	var break_edge: int
	var break_step: int
	var break_zone: int
	var current_step: int


## The defenders this swing can meet — immutable, built once by
## [method BladeDefenderZones.query], and possibly SHARED with every other
## proposal at the same pivot. Never mutated from here.
var zones: BladeDefenderZones = BladeDefenderZones.new()

## World-space centre / collision radius / source node of each zone. Forwarded
## rather than duplicated: [member zones] is the one copy.
var zone_centers: PackedVector2Array:
	get: return zones.centers
var zone_radii: PackedFloat32Array:
	get: return zones.radii
var zone_defenders: Array[SkillNode]:
	get: return zones.defenders

# ── Sim state (in Bank) ──────────────────────────────────────────────────────
## Per zone: accumulated unresolved drive (px) over the CURRENT contact. Reset
## to 0 the first substep the zone touches nothing, and after a break.
var _strain: PackedFloat32Array = PackedFloat32Array()
## Per zone: edge_idx -> load banked over the current contact, for the edges
## incident to what touched it. The strain's "which edge" answer.
var _edge_residual: Array[Dictionary] = []
## Where each driven particle ended the PREVIOUS substep, and where its driver
## had prescribed it then (both parallel to `_driven`); empty until one substep
## has run, so the first is unmeasured.
var _driven_last: PackedVector2Array = PackedVector2Array()
var _driven_last_target: PackedVector2Array = PackedVector2Array()
var _break_edge: int = -1
var _break_step: int = -1
var _break_zone: int = -1
var _current_step: int = 0

## The [Bank] at every sample of the chunk [method BladeSim.simulate_range] last
## ran this field over, parallel to that chunk's `samples` (`history[0]` is the
## bank on entry) — chunk-local and rebuilt every call, exactly like
## [member BladeSwingClock.history] and [member BladeState.speed_history]
## (#803). A break at local sample `j` rewinds with `restore(history[j])`, and
## because the break is armed by the substeps OF that sample, that bank already
## holds it armed: [method consume_break] then lands it with no head replay.
var history: Array[Bank] = []

# ── Per-run scratch (rebuilt by prepare / per substep) ──────────────────────
var _state: BladeState
var _clock: BladeSwingClock = null
var _driven: PackedInt32Array = PackedInt32Array()
var _driven_set: Dictionary = {}
var _driven_targets: PackedVector2Array = PackedVector2Array()
## particle -> zone, and edge_idx -> zone, for THIS substep. Cleared at its end.
var _contact_particles: Dictionary = {}
var _contact_edges: Dictionary = {}
## particle -> the outward normal it was last pushed along this substep.
var _contact_normals: Dictionary = {}
## zone -> true while some part is within CONTACT_HYSTERESIS of it this substep.
## PLATES only: a wall never enters this set, so it can never meter strain,
## arm a break or stall a grip (#811 — see the class docstring).
var _near: Dictionary = {}
## particle -> Array[int] of incident live edge indices. A reference-type
## Array on purpose: a packed array read back out of a Dictionary is a copy,
## and appending to it would be lost.
var _incident: Dictionary = {}

## Diagnostic trace for the classification test and the melee sandbox readout —
## off by default, costs nothing when off. Each entry is one substep with at
## least one contact: `[unresolved_drive, contact_unresolved]` — the metric in
## use, and the issue's first formulation for comparison.
var trace: bool = false
var trace_rows: Array[PackedFloat32Array] = []
var _trace_pre: PackedVector2Array = PackedVector2Array()


## False once this field was handed someone else's zone set — appending to a
## SHARED set would silently give a sibling proposal an extra defender.
var _owns_zones: bool = true


## Wrap [param zones_] — the production path, where the zone set arrives
## prebuilt (and possibly shared). Defaults to an empty own set that
## [method add_zone] / [method add_drag_zone] can then author into.
func _init(zones_: BladeDefenderZones = null) -> void:
	if zones_ != null:
		zones = zones_
		_owns_zones = false
	_size_accumulators()


func _size_accumulators() -> void:
	_strain.resize(zones.size())
	_edge_residual.clear()
	for _z in zones.size():
		_edge_residual.append({})


## Author one plate by hand — fixtures and the sandbox only; the production
## path builds its zones with [method BladeDefenderZones.query].
func add_zone(center: Vector2, radius: float, defender: SkillNode = null) -> void:
	_author(center, radius, 0.0, true, defender)


## Author one wall by hand, same caveat as [method add_zone].
func add_drag_zone(center: Vector2, radius: float, amount: float,
		defender: SkillNode = null) -> void:
	_author(center, radius, amount, false, defender)


## Author one node that is BOTH kinds — 18 of `first_level`'s 185 defender
## carriers are (#811), and neither shorthand above can express it. Same
## fixtures-and-sandbox caveat as those two. [b]Not the same as calling both[/b]:
## that would be two zones, and the once-per-swing drag latch keys on the zone
## index, so the wall would pay twice.
func add_defender_zone(center: Vector2, radius: float, drag: float, deflect: bool,
		defender: SkillNode = null) -> void:
	_author(center, radius, drag, deflect, defender)


func _author(center: Vector2, radius: float, drag: float, deflect: bool,
		defender: SkillNode) -> void:
	assert(_owns_zones, "cannot author into a SHARED BladeDefenderZones")
	zones.add(center, radius, drag, deflect, defender)
	_strain.resize(zones.size())
	while _edge_residual.size() < zones.size():
		_edge_residual.append({})


func has_zones() -> bool:
	return not zones.is_empty()


## Accumulated unresolved drive against zone [param z] right now, in px — the
## sandbox readout. 0 when nothing is touching it.
func strain(z: int) -> float:
	return _strain[z] if z >= 0 and z < _strain.size() else 0.0


func max_strain() -> float:
	var m := 0.0
	for s in _strain:
		m = maxf(m, s)
	return m


## Bind to the run about to step: which particles are driven (the pivot
## neighbours [BladeArcDriver] prescribes — read off the LIVE driver list, since
## [method MeleeAttackPlan._surviving_drivers] shrinks it after a severance) and
## the live edge incidence — plus [param clock], the swing's own accumulator,
## which [method project] banks a wall contact straight onto (#811; the clock
## owns the once-per-swing latch, so this class keeps no second one). Called by
## [method BladeSim.simulate_range] at the top of every call, including a head
## replay. A null clock means walls sense nothing: every production caller
## passes one whenever the zone set has a wall in it.
func prepare(state: BladeState, drivers: Array[BladeDriver],
		clock: BladeSwingClock = null) -> void:
	_state = state
	_clock = clock
	var driven := PackedInt32Array()
	_driven_set.clear()
	for d in drivers:
		var ad := d as BladeArcDriver
		if ad != null and not _driven_set.has(ad.particle):
			_driven_set[ad.particle] = true
			driven.append(ad.particle)
	if driven != _driven:
		# A different driven set makes the history non-parallel; skip one
		# substep's measurement rather than pair up the wrong particles.
		_driven_last = PackedVector2Array()
		_driven_last_target = PackedVector2Array()
	_driven = driven
	_driven_targets.resize(_driven.size())
	_incident.clear()
	for e_idx in state.edges.size():
		var e := state.edges[e_idx]
		if state.removed_edges.has(e_idx) \
				or state.removed_vertices.has(e.x) or state.removed_vertices.has(e.y):
			continue
		(_incident.get_or_add(e.x, [] as Array[int]) as Array[int]).append(e_idx)
		(_incident.get_or_add(e.y, [] as Array[int]) as Array[int]).append(e_idx)


## The GLOBAL index of the sample the next substeps produce.
func begin_sample(step: int) -> void:
	_current_step = step


## Snapshot the drivers' prescribed positions for this substep — called right
## after they apply, before the projection pass.
func after_drivers(positions: PackedVector2Array) -> void:
	for k in _driven.size():
		_driven_targets[k] = positions[_driven[k]]
	if trace:
		_trace_pre = positions.duplicate()


## The pushout, and the swing's only contact test. Runs once per solver
## iteration, after the distance constraints.
##
## [b]Both zone kinds walk the same geometry, once.[/b] For every zone this
## tests each blade vertex disc and each rim-trimmed edge capsule against the
## zone disc — the geometry [BladeHitScan] queries the physics server for and
## the geometry #780's deleted `BladeSwingClock.sense` re-implemented. What
## differs is what a contact DOES:
##
## - a plate (`deflects_at(z)`) is pushed out of, to within
##   [constant CONTACT_SLOP], and marks [member _near] so the strain meter runs;
## - a wall banks its drag on [member _clock] and is [b]skipped in the pushout
##   entirely[/b] — it never moves a vertex, never marks `_near`, and so can
##   never arm a break or stall a grip. A wall spends the swing's budget; it
##   does not stop the blade.
##
## A wall's contact test is the exact reach #780 used — `zone radius + particle
## radius` for a disc, `zone radius + EDGE_RADIUS` for a capsule, with no
## [constant CONTACT_SLOP] and no [constant CONTACT_HYSTERESIS] — so moving the
## sensing here did not move the boundary, only the cadence (per solver
## substep now, rather than per trajectory sample; strictly finer, and onset
## can only move earlier-or-equal).
##
## A wall also does not skip the pivot. The pushout does (`inv_masses[i] <= 0`:
## the pivot and any corpse are not pushed), but a fortified node overlapping
## the pivot did drag under #780 and still does.
func project(positions: PackedVector2Array, inv_masses: PackedFloat32Array) -> void:
	var edges := _state.edges
	var radii := _state.radii
	var removed_edges := _state.removed_edges
	var n := positions.size()
	if n == 0 or zones.is_empty():
		return
	# Broad phase, recomputed from THIS iteration's positions so it needs no
	# safety margin: a zone disc can only touch blade geometry inside the
	# blade's AABB grown by the widest blade disc, the edge half-thickness, the
	# hysteresis band and the zone's own radius. #811 widened the query radius
	# deliberately (see MeleeAttackPlan.whip_bound), so on a wall-heavy map this
	# field can hold dozens of zones while the blade is near none of them —
	# without this reject the per-iteration walk is O(zones x blade), measured
	# at +29% on a blade-size-4 prediction on `first_level`.
	var lo := positions[0]
	var hi := positions[0]
	var widest := 0.0
	for i in n:
		lo = lo.min(positions[i])
		hi = hi.max(positions[i])
		if i < radii.size():
			widest = maxf(widest, radii[i])
	var pad := widest + _EDGE_RADIUS + CONTACT_HYSTERESIS
	lo -= Vector2(pad, pad)
	hi += Vector2(pad, pad)
	for z in zones.size():
		var c := zones.centers[z]
		var zr := zones.radii[z]
		if c.x < lo.x - zr or c.x > hi.x + zr or c.y < lo.y - zr or c.y > hi.y + zr:
			continue
		var deflect := zones.deflects[z] != 0
		# A wall that has already banked has nothing left to learn — the same
		# early-out #780's `touched` check was, asked of the one latch that
		# exists now (the clock's).
		var wants_drag := zones.drags[z] > 0.0 and _clock != null \
				and not _clock.has_banked(z)
		if not deflect and not wants_drag:
			continue
		for i in n:
			var p := positions[i]
			var pr: float = radii[i] if i < radii.size() else 0.0
			var d2 := p.distance_squared_to(c)
			if wants_drag:
				var touch := zr + pr
				if d2 <= touch * touch:
					_clock.bank_drag(z, zones.drags[z])
					wants_drag = false
			if not deflect:
				continue
			if inv_masses[i] <= 0.0:
				continue  # the pivot, or a corpse — neither is pushed
			var reach := zr + pr - CONTACT_SLOP
			if d2 >= (reach + CONTACT_HYSTERESIS) * (reach + CONTACT_HYSTERESIS):
				continue
			_near[z] = true
			if d2 >= reach * reach:
				continue
			var d := sqrt(d2)
			var normal := (p - c) / d if d > 1e-6 else Vector2.RIGHT
			positions[i] = c + normal * reach
			_contact_particles[i] = z
			_contact_normals[i] = normal
		if not deflect and not wants_drag:
			continue  # wall, already banked by a disc — skip the capsule pass
		var cap_reach := zr + _EDGE_RADIUS
		for e_idx in edges.size():
			if removed_edges.has(e_idx):
				continue  # severed (#781) — a gone edge touches nothing
			var e := edges[e_idx]
			var a := positions[e.x]
			var b := positions[e.y]
			var delta := b - a
			var length := delta.length()
			var trimmed := length - radii[e.x] - radii[e.y]
			if trimmed < 1e-4:
				continue  # discs overlap — no exposed span (mirrors BladeHitScan)
			var dir := delta / length
			var p0 := a + dir * radii[e.x]
			var seg := dir * trimmed
			var u := clampf((c - p0).dot(seg) / (trimmed * trimmed), 0.0, 1.0)
			var q := p0 + seg * u
			var d2 := q.distance_squared_to(c)
			if wants_drag and d2 <= cap_reach * cap_reach:
				_clock.bank_drag(z, zones.drags[z])
				wants_drag = false
				if not deflect:
					break
			if not deflect:
				continue
			var wa := inv_masses[e.x]
			var wb := inv_masses[e.y]
			if wa + wb <= 0.0:
				continue
			if d2 >= (cap_reach + CONTACT_HYSTERESIS) * (cap_reach + CONTACT_HYSTERESIS):
				continue
			_near[z] = true
			if d2 >= cap_reach * cap_reach:
				continue
			var d := sqrt(d2)
			var normal := (q - c) / d if d > 1e-6 else Vector2(-dir.y, dir.x)
			var push := normal * (cap_reach - d)
			# q's barycentric coordinate along the FULL a..b segment.
			var sfrac := (radii[e.x] + trimmed * u) / length
			var wa_s := (1.0 - sfrac) * wa
			var wb_s := sfrac * wb
			var denom := (1.0 - sfrac) * wa_s + sfrac * wb_s
			if denom <= 0.0:
				continue
			positions[e.x] = a + push * (wa_s / denom)
			positions[e.y] = b + push * (wb_s / denom)
			_contact_edges[e_idx] = z


## Close the substep: stall the clock on a grip contact, meter the strain, arm a
## break, and roll the driver history.
func end_substep(positions: PackedVector2Array, clock: BladeSwingClock) -> void:
	if _near.is_empty():
		# Nothing anywhere near a plate: every contact is over. Reset, don't bank.
		for z in _strain.size():
			if _strain[z] != 0.0:
				_strain[z] = 0.0
				_edge_residual[z].clear()
		_roll_driven(positions)
		return
	if clock != null:
		for i in _contact_particles:
			if _driven_set.has(i):
				clock.stall()
				break
	# The unresolved drive: the most any grip particle fell short of the
	# advance its DRIVER made this substep (target now minus target then),
	# measured along that advance. A step that went BACKWARDS counts as fully
	# refused (capped at the request — a jammed body thrown back is not "more
	# stalled" than one held still); a step that caught up counts negative and
	# bleeds the bank.
	var unresolved := 0.0
	var any := false
	if _driven_last.size() == _driven.size():
		for k in _driven.size():
			var want := _driven_targets[k] - _driven_last_target[k]
			var req := want.length()
			if req <= 1e-6:
				continue
			var got := maxf(0.0, (positions[_driven[k]] - _driven_last[k]).dot(want / req))
			var u := req - got
			unresolved = u if not any else maxf(unresolved, u)
			any = true
	for z in _strain.size():
		if _near.has(z):
			_strain[z] = maxf(0.0, _strain[z] + unresolved)
		elif _strain[z] != 0.0:
			_strain[z] = 0.0
			_edge_residual[z].clear()
	# Load share, for "which edge": every live edge incident to a pushed vertex
	# banks the drive in proportion to how squarely the push runs along it.
	if unresolved > 0.0:
		for i in _contact_particles:
			var z: int = _contact_particles[i]
			var normal: Vector2 = _contact_normals[i]
			var inc: Array = _incident.get(i, [])
			for e_idx in inc:
				var e := _state.edges[e_idx]
				var other := e.y if e.x == i else e.x
				var dir := positions[other] - positions[i]
				var len := dir.length()
				if len <= 1e-6:
					continue
				_bank_load(z, e_idx, unresolved * absf(normal.dot(dir / len)))
		for e_idx in _contact_edges:
			_bank_load(_contact_edges[e_idx], e_idx, unresolved)
	if trace:
		trace_rows.append(PackedFloat32Array([unresolved, _contact_unresolved(positions)]))
	if _break_edge < 0:
		for z in _strain.size():
			if _strain[z] < SHATTER_DISTANCE:
				continue
			var e := _pick_edge(z)
			if e >= 0:
				_break_edge = e
				_break_step = _current_step
				_break_zone = z
				break
	_roll_driven(positions)


## True if a break was armed during the substeps of GLOBAL sample [param step].
func has_break_at(step: int) -> bool:
	return _break_edge >= 0 and _break_step == step


## Hand the armed break to the resolve loop and start every contact afresh —
## the structure just changed, so whatever was banked against it is stale.
## Null if nothing is armed.
func consume_break() -> Break:
	if _break_edge < 0:
		return null
	var b := Break.new()
	b.edge_idx = _break_edge
	b.step = _break_step
	b.defender = zone_defenders[_break_zone] if _break_zone < zone_defenders.size() else null
	_break_edge = -1
	_break_step = -1
	_break_zone = -1
	for z in _strain.size():
		_strain[z] = 0.0
		_edge_residual[z].clear()
	return b


func capture() -> Bank:
	var b := Bank.new()
	b.strain = _strain.duplicate()
	b.edge_residual = []
	for d in _edge_residual:
		b.edge_residual.append(d.duplicate())
	b.driven_last = _driven_last.duplicate()
	b.driven_last_target = _driven_last_target.duplicate()
	b.break_edge = _break_edge
	b.break_step = _break_step
	b.break_zone = _break_zone
	b.current_step = _current_step
	return b


func restore(b: Bank) -> void:
	if b == null:
		return
	_strain = b.strain.duplicate()
	_edge_residual = []
	for d in b.edge_residual:
		_edge_residual.append(d.duplicate())
	_driven_last = b.driven_last.duplicate()
	_driven_last_target = b.driven_last_target.duplicate()
	_break_edge = b.break_edge
	_break_step = b.break_step
	_break_zone = b.break_zone
	_current_step = b.current_step
	_contact_particles.clear()
	_contact_edges.clear()
	_contact_normals.clear()
	_near.clear()


# ── The native boundary (#813) ────────────────────────────────────────────────
# The C++ backend runs [method project] and [method end_substep] itself rather
# than calling back into GDScript per solver iteration — a callback there fires
# in the innermost loop, and the crossing would eat most of the 22x this exists
# to unlock. So the field crosses as data: the immutable half once
# ([method native_inputs]), the accumulators in and out
# ([method native_state] / [method apply_native_state]), and one Bank-shaped
# Dictionary per sample back ([method bank_from_native]).
#
# These are [method capture] / [method restore] in Dictionary clothing. Change
# them together with those two and with the C++ `FieldCtx`: a field that stops
# crossing is not an error on either side, it is a silently different swing.


## False when this field is outside the native backend's transliterated subset,
## so [method BladeSim.simulate_range] falls back. Only [member trace] takes it
## out: the diagnostic rows feed the classification test and the melee sandbox
## readout, both of which run one swing at a time, so the GDScript path is
## exactly the right place for them.
func native_supported() -> bool:
	return not trace


## The immutable half of the run about to step: the zone set, the live edge set,
## the driven particles, the incidence [method prepare] just built, and the four
## tuning constants. The constants are PASSED rather than restated in C++ so each
## keeps one definition — the same reason `length_factor` is precomputed (#798).
func native_inputs() -> Dictionary:
	var edge_count := _state.edges.size()
	var edges_flat := PackedInt32Array()
	edges_flat.resize(edge_count * 2)
	var edge_removed := PackedByteArray()
	edge_removed.resize(edge_count)
	for e_idx in edge_count:
		var e := _state.edges[e_idx]
		edges_flat[e_idx * 2] = e.x
		edges_flat[e_idx * 2 + 1] = e.y
		edge_removed[e_idx] = 1 if _state.removed_edges.has(e_idx) else 0
	# `_incident` as a CSR over particles. The per-particle lists stay in the
	# ascending-edge-index order [method prepare] appended them in, because the
	# load share sums into shared edge banks in that order — this is summation
	# order, not merely a layout.
	var n := _state.positions.size()
	var incident_offsets := PackedInt32Array()
	incident_offsets.resize(n + 1)
	var incident_edges := PackedInt32Array()
	for i in n:
		incident_offsets[i] = incident_edges.size()
		var inc: Array = _incident.get(i, [])
		for e_idx: int in inc:
			incident_edges.append(e_idx)
	incident_offsets[n] = incident_edges.size()
	return {
		"has_field": true,
		"has_clock": _clock != null,
		"clock_duration": _clock.duration if _clock != null else 0.0,
		"zone_centers": zones.centers,
		"zone_radii": zones.radii,
		"zone_drags": zones.drags,
		"zone_deflects": zones.deflects,
		"edges": edges_flat,
		"edge_removed": edge_removed,
		"vertex_radii": _state.radii,
		"driven": _driven,
		"incident_offsets": incident_offsets,
		"incident_edges": incident_edges,
		"contact_slop": CONTACT_SLOP,
		"contact_hysteresis": CONTACT_HYSTERESIS,
		"shatter_distance": SHATTER_DISTANCE,
		"edge_radius": _EDGE_RADIUS,
	}


## The accumulators as plain values — the same eight fields [Bank] carries.
func native_state() -> Dictionary:
	var residual: Array = []
	for d: Dictionary in _edge_residual:
		residual.append(d.duplicate())
	return {
		"strain": _strain.duplicate(),
		"edge_residual": residual,
		"driven_last": _driven_last.duplicate(),
		"driven_last_target": _driven_last_target.duplicate(),
		"break_edge": _break_edge,
		"break_step": _break_step,
		"break_zone": _break_zone,
		"current_step": _current_step,
	}


## Turn one of the C++ loop's per-sample Dictionaries back into a [Bank].
static func bank_from_native(d: Dictionary) -> Bank:
	var b := Bank.new()
	b.strain = d["strain"]
	b.edge_residual = []
	for e: Dictionary in (d["edge_residual"] as Array):
		b.edge_residual.append(e)
	b.driven_last = d["driven_last"]
	b.driven_last_target = d["driven_last_target"]
	b.break_edge = d["break_edge"]
	b.break_step = d["break_step"]
	b.break_zone = d["break_zone"]
	b.current_step = d["current_step"]
	return b


## Adopt the state the C++ loop left — the inverse of [method native_state], and
## what lets [method consume_break] land a natively-armed break unchanged.
func apply_native_state(d: Dictionary) -> void:
	_strain = d["strain"]
	_edge_residual = []
	for e: Dictionary in (d["edge_residual"] as Array):
		_edge_residual.append(e)
	_driven_last = d["driven_last"]
	_driven_last_target = d["driven_last_target"]
	_break_edge = d["break_edge"]
	_break_step = d["break_step"]
	_break_zone = d["break_zone"]
	_current_step = d["current_step"]
	# The per-substep scratch never survives a substep on either path; clearing
	# it here mirrors [method restore] rather than leaving GDScript's stale.
	_contact_particles.clear()
	_contact_edges.clear()
	_contact_normals.clear()
	_near.clear()


func _roll_driven(positions: PackedVector2Array) -> void:
	_driven_last.resize(_driven.size())
	_driven_last_target.resize(_driven.size())
	for k in _driven.size():
		_driven_last[k] = positions[_driven[k]]
		_driven_last_target[k] = _driven_targets[k]
	_contact_particles.clear()
	_contact_edges.clear()
	_contact_normals.clear()
	_near.clear()


func _bank_load(z: int, e_idx: int, r: float) -> void:
	var d := _edge_residual[z]
	d[e_idx] = float(d.get(e_idx, 0.0)) + r


## The most strained live edge banked against zone [param z], lowest index on
## a tie; -1 if nothing is left to break there.
func _pick_edge(z: int) -> int:
	var best := -1
	var best_r := -1.0
	var keys := _edge_residual[z].keys()
	keys.sort()
	for e_idx in keys:
		if _state.removed_edges.has(e_idx):
			continue
		var r: float = _edge_residual[z][e_idx]
		if r > best_r:
			best_r = r
			best = e_idx
	return best


## Diagnostic only: the issue's first metric — the contacting vertices' own
## unresolved pushout (`required - |F - P|`, max over contacts) this substep.
func _contact_unresolved(positions: PackedVector2Array) -> float:
	if _trace_pre.is_empty():
		return 0.0
	var worst := 0.0
	for i in _contact_particles:
		var z: int = _contact_particles[i]
		var p := _trace_pre[i]
		var required := zone_radii[z] + _state.radii[i] - CONTACT_SLOP - p.distance_to(zone_centers[z])
		var actual := positions[i].distance_to(p)
		worst = maxf(worst, required - actual)
	return worst
