class_name BladeDefenderZones
extends RefCounted

## The defenders one swing can meet, found ONCE by the physics engine (#811).
##
## [b]One question, one query.[/b] "Which nodes near this swing carry
## `swing_drag` or `deflection`?" used to be asked twice — [method
## MeleeAttackPlan.build_swing_clock] and [method
## MeleeAttackPlan.build_obstacle_field] each walked all 800 [SkillNode]s and
## resolved a stat on every one, then culled by a rest-pose radius that
## measured 65% short of a whipped blade's real reach (#808). Since #810 the
## predicate lives on the physics layer bits [constant
## SkillNode.DRAG_COLLISION_LAYER] / [constant SkillNode.DEFLECT_COLLISION_LAYER],
## so both walks collapse into a single [method
## PhysicsDirectSpaceState2D.intersect_shape] against a mask of both bits, and
## the radius stops being what makes the work cheap.
##
## [b]Immutable, and that is what makes it shareable.[/b] Nothing here is sim
## state: [BladeObstacleField] wraps an instance of this and owns every mutable
## accumulator, [BladeSwingClock] owns the drag it has banked. So one instance
## can be built per PIVOT and handed to all of that pivot's rollout proposals
## ([AiBladeRollout] evaluates up to 192, concurrently, in
## [WorkerThreadPool] tasks) without either half racing the other — the query
## runs on the main thread, the solver reads plain arrays.
##
## [b]Two kinds, one zone.[/b] A node that carries both stats is ONE entry that
## is both a wall and a plate, never two — the latch that stops a zone paying
## its drag twice keys on the zone index, so a double-counted node would double
## its wall. The kinds are asymmetric on purpose: `deflection` is a BOOL stat
## (presence only, §805), `swing_drag` is a magnitude.
##
## [b]Order is by [member SkillNode.stable_id], and that is a contract.[/b]
## [method PhysicsDirectSpaceState2D.intersect_shape] returns colliders in
## whatever order the broadphase found them — undefined, and not reproducible
## across machines. Two first-wins tie-breaks read this order ([member
## BladeSwingClock._warping]'s seeding, and which zone arms a break first in
## [method BladeObstacleField.end_substep]), so a mirror peer redrawing the
## swing must see the same one. The old walks were implicitly scene-child
## ordered; this is explicit. See `test/unit/attack/test_attack_determinism.gd`.

## How much longer than its summed rest edge lengths a whipped blade is assumed
## to be able to get. XPBD's distance constraints are soft, so a fast sweep
## stretches the chain a few percent past rest before they pull it back.
##
## [b]This is a coverage margin, not a bound anyone relies on being tight.[/b]
## With the predicate on the collision mask, widening the query costs only the
## solver's per-zone [code]_near[/code] walk — never an O(map) stat resolve — so
## the degradation is graceful in one direction only: too small silently drops
## a defender the blade really reaches (that was #808's bug), too large costs a
## few float compares per substep. Err large.
const STRETCH_MARGIN: float = 1.10

## World-space centre and collision radius of each defender, parallel arrays —
## exactly like [member BladeState.positions].
var centers: PackedVector2Array = PackedVector2Array()
var radii: PackedFloat32Array = PackedFloat32Array()
## Per zone: its `swing_drag` magnitude, 0.0 for a zone that is not a wall.
var drags: PackedFloat32Array = PackedFloat32Array()
## Per zone: 1 iff its `deflection` is true — a bunker plate the swing is
## pushed out of. [PackedByteArray] rather than [code]Array[bool][/code]: this
## is read once per zone per solver iteration.
var deflects: PackedByteArray = PackedByteArray()
## Per zone: the node it came from, for a [BladeObstacleField.Break]'s
## `defender`. May hold nulls in fixtures that author zones by hand.
var defenders: Array[SkillNode] = []

var _has_drag: bool = false
var _has_deflection: bool = false


## Append one defender. `drag` is its `swing_drag` (0 for none), `deflect` its
## `deflection`. A zone with neither is not a defender and is rejected.
func add(center: Vector2, radius: float, drag: float, deflect: bool,
		defender: SkillNode = null) -> void:
	if drag <= 0.0 and not deflect:
		return
	centers.append(center)
	radii.append(radius)
	drags.append(maxf(drag, 0.0))
	deflects.append(1 if deflect else 0)
	defenders.append(defender)
	_has_drag = _has_drag or drag > 0.0
	_has_deflection = _has_deflection or deflect


func size() -> int:
	return radii.size()


func is_empty() -> bool:
	return radii.is_empty()


## True if any zone is a wall — i.e. this swing needs a [BladeSwingClock].
func has_drag() -> bool:
	return _has_drag


## True if any zone is a plate — i.e. the pushout and the strain meter have
## something to act on.
func has_deflection() -> bool:
	return _has_deflection


func deflects_at(z: int) -> bool:
	return z >= 0 and z < deflects.size() and deflects[z] != 0


## Every defender node whose own disc overlaps a disc of [param radius] centred
## on [param center], in [member SkillNode.stable_id] order.
##
## [param exclude] is the blade side's RIDs — the same list [BladeHitScan] is
## given, from [method MeleeAttackPlan.collect_target_excludes], so "a node I
## or an ally own never defends against my own swing" is answered once rather
## than by a second membership predicate. [param graph] resolves stable ids and
## is what keeps the order defined; it may be null in a fixture, in which case
## the nodes' own [member SkillNode.stable_id] is used.
##
## [b]Main thread only.[/b] A physics-server query is not safe from a
## [WorkerThreadPool] task; the whole point of this class is that the result is
## plain data the solver can then consume from one.
static func query(
		space_state: PhysicsDirectSpaceState2D,
		center: Vector2,
		radius: float,
		exclude: Array[RID] = [],
		graph: Graph = null) -> BladeDefenderZones:
	var zones := BladeDefenderZones.new()
	if space_state == null or radius <= 0.0:
		return zones
	var shape := CircleShape2D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, center)
	# Both defender bits (#810). Layer 1 — every SkillNode, always — is
	# deliberately NOT in the mask: that is what makes this query O(defenders)
	# rather than O(map).
	params.collision_mask = (1 << (SkillNode.DRAG_COLLISION_LAYER - 1)) \
			| (1 << (SkillNode.DEFLECT_COLLISION_LAYER - 1))
	# A SkillNode's root IS the Area2D (skill_node.tscn) — mirrors BladeHitScan.
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.exclude = exclude
	var hits := space_state.intersect_shape(params, _MAX_ZONES)
	if hits.size() >= _MAX_ZONES:
		push_warning("BladeDefenderZones: hit the %d-zone query cap at radius %.0f — some defenders were dropped"
				% [_MAX_ZONES, radius])
	var found: Array[SkillNode] = []
	for hit in hits:
		var sn := hit.get("collider") as SkillNode
		if sn != null:
			found.append(sn)
	found.sort_custom(func(a: SkillNode, b: SkillNode) -> bool:
		var a_id := graph.get_stable_id(a) if graph != null else a.stable_id
		var b_id := graph.get_stable_id(b) if graph != null else b.stable_id
		return a_id < b_id)
	for sn in found:
		zones.add(
				sn.global_position, sn.radius,
				float(sn.get_local_value(&"swing_drag")),
				bool(sn.get_local_value(&"deflection")),
				sn)
	return zones


## The cap handed to [method PhysicsDirectSpaceState2D.intersect_shape], which
## defaults to 32 and silently truncates. Measured on `first_level` (800 nodes,
## the densest map that ships, seed 0x57A17EE): [b]114[/b] nodes carry
## `swing_drag`, [b]89[/b] carry `deflection`, [b]18[/b] carry both — 185
## distinct carriers MAP-WIDE, and a whole-map query is the worst case any
## radius can reach. 512 is comfortably above that, so the result is bounded by
## the mask and never by this. The push_warning above is the alarm if a future
## map passes it. See `test/perf/bench_melee_prediction_cost.gd`'s
## `test_defender_carrier_count_on_first_level`, which is that measurement.
const _MAX_ZONES := 512
