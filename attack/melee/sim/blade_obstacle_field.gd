class_name BladeObstacleField
extends BladeConstraint

## The defender field: the one object in the solver that tests the blade
## against a defender node, wrapping one immutable [BladeDefenderZones]. Two
## zone kinds, asymmetric on purpose — a [b]plate[/b] (`deflection`, presence
## only) is pushed out of, meters strain, arms a break and can stall the grip;
## a [b]wall[/b] (`swing_drag`, a magnitude) is only SENSED: [method project]
## skips it and its drag is banked on the [BladeSwingClock]. A wall never
## enters [member _near] and never shatters a blade. A node carrying both stats
## is one zone that is both kinds, latched once.
##
## Invariants: exists only when some defender is inside the swing's whip bound
## (no defender, no field, no accumulator — the false-positive guard is
## structural); projected every solver iteration AFTER the distance
## constraints; strain is the DRIVER's unresolved advance, never a contact
## residual; what breaks is an EDGE (the most loaded incident one), recorded
## as a PENDING request and severed by the resolve loop, never by this class;
## a contact on a driven particle stalls the clock instead of breaking;
## [method capture] / [method restore] make it rewindable exactly like
## [BladeSwingClock.Bank]; analytic and allocation-free per substep with no
## physics-server calls, so a worker-thread rollout may share one zone set.
## See docs/domain/melee-blade-sim.md, "Bunker deflection".

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

## Per zone: the `swing_drag` magnitude and the `deflection` flag THE SOLVER
## SEES — the authored values until this swing disowns a defender (#867), zero
## from that moment on. Both backends read these and never [member zones]'
## own.
##
## [b]Not a second copy of the zone set.[/b] A packed-array assignment in
## GDScript is copy-on-write, so these share `zones`' storage byte for byte
## until the first retirement writes a zero into one — which is what lets the
## shared, immutable `zones` (up to 192 sibling [AiBladeRollout] proposals may
## hold the same instance, concurrently) stay untouched without every ordinary
## swing paying for a duplicate.
##
## [b]Deliberately NOT in [Bank].[/b] Retirement is a fact about the world, not
## sim state: the resolve loop's rewind restores the accumulators to an earlier
## sample and must never resurrect a defender the swing has already destroyed.
var _live_drags: PackedFloat32Array = PackedFloat32Array()
var _live_deflects: PackedByteArray = PackedByteArray()

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
	_adopt_authored_zone_values()


## Point [member _live_drags] / [member _live_deflects] at what the zone set
## currently authors. Called wherever the zone COUNT changes — construction and
## [method _author] — never after a retirement, which would undo it.
func _adopt_authored_zone_values() -> void:
	_live_drags = zones.drags
	_live_deflects = zones.deflects


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
	_adopt_authored_zone_values()


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
## [method SwingResolve._surviving_drivers] shrinks it after a severance) and
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
		var deflect := _live_deflects[z] != 0
		# A wall that has already banked has nothing left to learn — the same
		# early-out #780's `touched` check was, asked of the one latch that
		# exists now (the clock's).
		var wants_drag := _live_drags[z] > 0.0 and _clock != null \
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
					_clock.bank_drag(z, _live_drags[z])
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
				_clock.bank_drag(z, _live_drags[z])
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


## True if some zone the solver is still honouring has lost its allocation in
## [param world] (#867) — the resolve loop's cue that the bake in flight was
## computed against a defender that no longer exists and has to be thrown away.
##
## O(zones in reach), and the loop only asks it on a sample that actually landed
## a hit, because a cascade has no other door into a swing.
func has_disowned_defender(world: CombatWorld) -> bool:
	for z in zones.size():
		if _is_disowned(z, world):
			return true
	return false


## Drop every defender that is no longer allocated in [param world] out of the
## solver's view: from here on its drag banks nothing and its plate pushes
## nothing, which is #867's "an unallocated node never interacts with an
## incoming blade" applied live instead of only at swing start.
##
## [b]Idempotent and monotone[/b] — a retired zone can never come back, so the
## resolve loop may call this at every boundary without tracking which zones it
## has already handled. Everything else about the zone survives: its centre, its
## radius, its `defender` (so a [Break] already armed can still name it), and
## any drag its wall had already banked on the clock. "Stops mattering from the
## moment it deallocates" is not "never mattered".
##
## [b]Call it AFTER [method restore][/b]. The bank a severance rewinds to
## carries the pre-death strain and any armed break; retiring first would simply
## be undone.
func retire_disowned_defenders(world: CombatWorld) -> void:
	for z in zones.size():
		if not _is_disowned(z, world):
			continue
		_live_drags[z] = 0.0
		_live_deflects[z] = 0
		# Whatever was banked against it is meaningless now — the same reset
		# [method consume_break] performs, for the same reason.
		_strain[z] = 0.0
		_edge_residual[z].clear()
		if _break_zone == z:
			# A plate that no longer exists breaks nothing.
			_break_edge = -1
			_break_step = -1
			_break_zone = -1


## Whether zone [param z] is still armed as a defender yet no longer allocated.
##
## [b]Allocation is asked of the WORLD, never of the real [SkillNode].[/b] The
## authority resolves on a shadow, where the cascade strips
## [member NodeCombat._owner] and leaves `owned_by` on the real node untouched
## until the record is replayed — so a live-node read would keep honouring a
## defender this very swing has already destroyed. Same rule
## [method BladePopResolver.LiveGate.admit] follows; see
## docs/domain/attack-timeline.md.
func _is_disowned(z: int, world: CombatWorld) -> bool:
	if _live_drags[z] <= 0.0 and _live_deflects[z] == 0:
		return false  # already retired, or never a defender of either kind
	if world == null:
		return false
	# Null in a fixture that authored its zones by hand — there is no node to
	# ask, and such a zone is the fixture's own business.
	var sn: SkillNode = zones.defenders[z] if z < zones.defenders.size() else null
	if sn == null:
		return false
	var slice := world.combat_for(sn)
	return slice == null or not slice.is_allocated()


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
		"zone_drags": _live_drags,
		"zone_deflects": _live_deflects,
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


