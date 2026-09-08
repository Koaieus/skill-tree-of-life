class_name BladeState
extends RefCounted

## Pure descriptor handed to BladeSim. Constructed once per simulate() call.
## Mutates in place during stepping — positions advance, prev_positions
## get rewritten. Re-build before re-running if you need a fresh start.

var positions: PackedVector2Array
var prev_positions: PackedVector2Array
var inv_masses: PackedFloat32Array
var radii: PackedFloat32Array
## Inner-disk radius per particle, mirroring [member SkillNode.inner_radius] —
## the geometric companion to [member radii] (the outer radius). Sim-inert
## (no constraint reads it); carried purely so the visual layer can draw a
## blade node's disc + rim band matching the SkillNode it was built from.
var inner_radii: PackedFloat32Array
## Per-particle blade damage — a COEFFICIENT, not the final landing amount
## (#779; was the full per-contact amount before speed-scaled damage). Zeroed
## in build(); the caller fills each slot from the source SkillNode's
## get_local_value(&"blade_damage") (which already merges the wielder's base +
## any node-local spike modifiers). A hit site turns this into the actual
## damage by multiplying with [method speed_damage_multiplier] at the
## contacting vertex's own contact-time speed — no base added on top, but a
## curve now sits between this value and what lands.
var vertex_damage: PackedFloat32Array
## Per-particle contact speed (px/s), one entry per trajectory sample —
## `speed_history[k]` parallels what `BladeTrajectory.samples[k]` would be,
## index for index. Reset to a single all-zero entry (for the pre-step pose,
## matching `samples[0]`'s "before any solver step" meaning, #633) at the top
## of every [method BladeSim.simulate] call, then appended to once per sample
## interval — never accumulated across separate `simulate()` calls.
##
## Each appended entry is the LAST substep's per-particle speed for that
## interval — the physics rate, not the sample rate (#779; see
## `BladeSim._step`'s `sp_sq` and `docs/domain/melee-blade-sim.md`'s
## speed-scaled damage section for why an average or a per-step max would be
## wrong here). [BladeHitScan] reads this to stamp each [BladeHitEvent]'s
## contact speed.
var speed_history: Array[PackedFloat32Array] = []
## Per-particle blunting — how much of a spiked defender's remaining `spikes`
## pool this vertex drains on contact, and the threshold it must fully clear to
## pop (#778). The defensive counterpart of [member vertex_damage], filled the
## same way: zeroed in build(), then each slot written by the caller from the
## source SkillNode's get_local_value(&"blunting") (wielder board baseline
## merged with any node-local [SpikeRingAddon] grant).
##
## Zero means UNFILLED, not "blunting 0" — a 0 would drain nothing and pop
## nothing, which is not a state any node can author. Callers that build a
## state without naming source nodes (fixtures, characterization tests) simply
## leave the array zeroed, and [method BladePopResolver.LiveGate._blunting_for]
## falls back to the `blunting` [StatDef]'s own default.
var vertex_blunting: PackedFloat32Array
## Per-EDGE damage coefficient — the exact counterpart of [member
## vertex_damage], one slot per entry of [member edges], and read the same way
## (a hit site multiplies it by [method speed_damage_multiplier]). Zeroed in
## [method build]; both blade-build call sites fill each slot with the MIN of
## its two endpoints' `get_local_value(&"edge_damage")`.
##
## Min, not sum/max/lerp, because the sharpener is PAIRED: an edge is sharp
## only if both of its ends carry the grant, which falls straight out of a min
## and needs no per-edge addon hook. The `edge_damage` StatDef defaults to 0,
## so an unsharpened blade's edges collide but deal nothing (#785 acceptance 4).
var edge_damage: PackedFloat32Array
var pivot_index: int = 0
var edges: Array[Vector2i] = []
## Severed edge indices — `edges` itself is never spliced, because a
## [BladeHitEvent] carries an `edge_idx` INTO it and a splice would silently
## re-point every pending event past the removal. So removal is recorded here
## instead: an index in this set is gone for every purpose ([method
## BladePopResolver._reachable_from_pivot] does not traverse it, [BladeHitScan]
## does not query it, its distance constraint is dropped by [method
## remove_edge]). #781's bunker break writes here too.
var removed_edges: Dictionary = {}
var constraints: Array[BladeConstraint] = []


## Build a state from particle data and a list of edges. Seeds one
## BladeDistanceConstraint per edge (rest = initial distance, fully rigid).
## Callers can append further constraints after this returns.
##
## `inner_radii_` is optional — sim callers that never spawn visuals (fixtures,
## [MeleeAttackPlan]'s headless simulate) can omit it; it then mirrors
## `radii_` (inner == outer, i.e. no rim band), which [BladeCircle] draws as a
## flat fill rather than a degenerate zero-width stroke.
static func build(
		positions_: Array[Vector2],
		pivot_idx: int,
		edges_: Array[Vector2i],
		radii_: Array[float],
		inner_radii_: Array[float] = []) -> BladeState:
	var s := BladeState.new()
	s.positions = PackedVector2Array(positions_)
	s.pivot_index = pivot_idx
	s.edges = edges_
	s.radii = PackedFloat32Array(radii_)
	s.inner_radii = PackedFloat32Array(inner_radii_ if not inner_radii_.is_empty() else radii_)
	s.vertex_damage = PackedFloat32Array()
	s.vertex_damage.resize(positions_.size())  # zero-init; caller fills per-vertex
	s.vertex_blunting = PackedFloat32Array()
	s.vertex_blunting.resize(positions_.size())  # zero-init == unfilled; see the member
	s.edge_damage = PackedFloat32Array()
	s.edge_damage.resize(edges_.size())  # zero-init; an unsharpened edge deals 0
	s.inv_masses = PackedFloat32Array()
	s.inv_masses.resize(positions_.size())
	for i in positions_.size():
		s.inv_masses[i] = 0.0 if i == pivot_idx else 1.0
	for e in edges_:
		var rest := positions_[e.x].distance_to(positions_[e.y])
		s.constraints.append(BladeDistanceConstraint.new(e.x, e.y, rest))
	return s


## True if [param edge_idx] has been severed this swing — see [member
## removed_edges].
func is_edge_removed(edge_idx: int) -> bool:
	return removed_edges.has(edge_idx)


## Sever [param edge_idx]: mark it in [member removed_edges] and drop its
## [BladeDistanceConstraint], so a re-run of the sim no longer holds its
## endpoints together. Idempotent. Returns true if this call did the removing.
##
## The constraint is matched on its (a, b) endpoint pair rather than by index:
## [method build] seeds constraints one-per-edge in order, but addons append
## further constraints afterwards (ClampAddon's phantom brace), so index parity
## between `edges` and `constraints` is not a promise this class makes. A brace
## is deliberately NOT dropped — it is not this edge.
##
## Callers driving a [BladePopResolver.LiveGate] must follow this with
## [method BladePopResolver.LiveGate.invalidate_adjacency]; the gate's own
## sever path already does.
func remove_edge(edge_idx: int) -> bool:
	if edge_idx < 0 or edge_idx >= edges.size() or removed_edges.has(edge_idx):
		return false
	removed_edges[edge_idx] = true
	var e := edges[edge_idx]
	for i in constraints.size():
		var dc := constraints[i] as BladeDistanceConstraint
		if dc == null:
			continue
		if (dc.a == e.x and dc.b == e.y) or (dc.a == e.y and dc.b == e.x):
			constraints.remove_at(i)
			break
	return true


## Hop count from the pivot to the farthest vertex, walking `constraints`
## (not `edges`) — a phantom brace (ClampAddon's weld) shortens the path a
## correction has to travel just as much as a real edge does, so the fidelity
## budget in [BladeSim] must see it too. One BFS, O(vertices + constraints);
## do not call this per-iteration or per-particle — [BladeSim.simulate] calls
## it once per resolve and reuses the result for the whole swing.
##
## Only [BladeDistanceConstraint] contributes adjacency (the sole concrete
## [BladeConstraint] today); a future constraint type that doesn't connect
## exactly two particles is invisible to this walk by construction.
func pivot_eccentricity() -> int:
	var adjacency: Dictionary = {}
	for c in constraints:
		if c is BladeDistanceConstraint:
			var dc := c as BladeDistanceConstraint
			adjacency.get_or_add(dc.a, [] as Array[int]).append(dc.b)
			adjacency.get_or_add(dc.b, [] as Array[int]).append(dc.a)
	var hops := {pivot_index: 0}
	var queue: Array[int] = [pivot_index]
	var max_hops := 0
	var qi := 0
	while qi < queue.size():
		var cur: int = queue[qi]
		qi += 1
		var h: int = hops[cur]
		if h > max_hops:
			max_hops = h
		for nb in adjacency.get(cur, [] as Array[int]):
			if not hops.has(nb):
				hops[nb] = h + 1
				queue.append(nb)
	return max_hops


## Speed-scaled damage curve (#779) — the saturating hyperbolic the owner
## pinned 2026-09-08: `f(v) = 1 + (M - 1) * v / (v + v_half)`.
##
## `f(0) == 1.0` exactly, floored — a stationary vertex deals its base
## coefficient, never a penalty. `f(v_half) == 1 + (m-1)/2` (half the bonus
## collected); `f(v -> inf) -> m` (bounded, never "infinite speed means
## infinite damage" per the owner's filing comment). Floored at `1.0`
## unconditionally, even if a misconfigured `m < 1.0` would otherwise produce
## a penalty — that variant is explicitly parked (#772 pt. 2 NOTES), not this
## issue's to build.
##
## A static helper taking raw numbers, not a [BladeHitEvent] or a
## [StatBoard], so an edge hit (#785 — not landed; edges have no collision
## yet) can reuse the identical curve once it exists, instead of a second
## inlined copy.
static func speed_damage_multiplier(speed: float, m: float, v_half: float) -> float:
	var denom := speed + v_half
	if denom <= 0.0:
		# Degenerate config (v_half <= 0 and a zero/negative speed) — never
		# divide by zero; a slow vertex still deals its base coefficient.
		return 1.0
	var f := 1.0 + (m - 1.0) * speed / denom
	return maxf(1.0, f)


## Read a scalar stat off [param board] by [param id], falling back to
## [param fallback] when the board or the stat itself is missing (a headless
## fixture, an unowned preview blade with no wielder). Mirrors [method
## CritRoll.multiplier_for]'s same guard, kept local rather than shared
## because this unit owns no file [CritRoll] lives in.
static func stat_value(board: StatBoard, id: StringName, fallback: float) -> float:
	if board == null:
		return fallback
	var stat: Stat = board.get_stat(id)
	if stat == null:
		return fallback
	return stat.get_value()
