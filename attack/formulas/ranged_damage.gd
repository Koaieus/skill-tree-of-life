class_name RangedDamageFormula

## Pure-function damage formula for a single ranged shot. One hit per firing
## position; RangedAttackPlan.resolve() loops the authored firing schedule
## and accumulates DamageInstances.
##
## Per-shot model deliberately: lets future flat armour reduce each impact
## instead of one big number, and supports staggered VFX hits.
##
## Reads `ranged_damage` from the firing node's local stat board — the
## entity board intrinsic formula (`floor(DEX / 10.0)`) plus any node-local
## addons contribute to the value, so the UI and resolver stay dumb.
##
## Timing is NOT this function's job — see docs/domain/attack-timeline.md
## "The ranged volley ramp". `arrival_time` used to be `distance /
## PROJECTILE_SPEED`, which let allocation order leak into combat outcome
## (a near leaf firing third could still land before a far leaf firing
## first). The ramp is authored against the volley's own distance span
## instead: RangedAttackPlan.resolve() normalizes each reaching leaf's
## distance to target into 0..1 across [d_min, d_max] and stamps
## `arrival_time` from the constants below. `compute()` leaves it at the
## HitInstance default (0.0) — it is filled in exactly once, by the caller
## that knows the whole volley's span.

## Constant per-shot flight duration (s) — every shot takes the same time to
## land regardless of distance. The fiction is the arc: a point-blank shot
## is lobbed nearly straight up, a distant one goes nearly flat, and both
## take about the same time to come down. This is what makes arrival order
## == firing order == distance order UNCONDITIONALLY (a distance-scaled
## flight speed could invert it). Also the animation's per-shot speed is now
## derived (`distance / FLIGHT_TIME`) rather than driving the schedule.
const FLIGHT_TIME: float = 0.8

## Total span (s) the launch ramp covers, nearest-to-target leaf to
## furthest-reaching leaf — fixed regardless of shot count, so a 4-shot and
## a 100-shot volley take the same wall time and stay readable rather than
## crawling. Also fixed regardless of how the leaves are DISTRIBUTED inside
## it: only the two extremes pin the window; everything else lands wherever
## its own distance falls. Verified against
## ArrowVolleyCoordinator.MIN_FLIGHT_FRACTION's clamp in
## test_arrow_volley_coordinator.gd — see the issue's "Watch" note.
const TOTAL_STAGGER: float = 0.7

## Windup before the first release. 0.0 for now, per the issue's settled
## design — authored in from the start so a draw phase can be turned on
## without re-deriving the schedule.
const DRAW_TIME: float = 0.0

static func compute(attacker: Entity, firing_node: SkillNode, target: SkillNode) -> DamageInstance:
	var hit := RangedHitInstance.new()
	hit.attacker = attacker
	hit.type = DamageInstance.Type.PHYSICAL
	hit.target = target
	hit.origin = firing_node
	hit.amount = _read_offense(firing_node)
	return hit


## Shared by [method compute] (the resolve-time PREVIEW read — AI scoring,
## tooltips) and [RangedHitInstance.land_on] (the land-time LIVE read, #503)
## so the two can never drift into two implementations of "what does this
## firing node's shot deal".
static func _read_offense(firing_node: SkillNode) -> float:
	if firing_node == null:
		return 0.0
	return float(firing_node.get_local_value(&"ranged_damage"))


## Ranged's land-time gate + live-offense read (#503) — the ranged sibling of
## [BladeDamageInstance] (#502, `attack/melee/sim/blade_damage_instance.gd`).
## [method compute] stays pure and up-front: the `amount` it stamps is only
## ever a resolve-time PREVIEW (AI scoring, tooltips). The live re-check and
## the live `ranged_damage` read both happen here, in [method land_on],
## called once per hit by [OutcomeApplier] in [member HitInstance.arrival_time]
## order (docs/domain/attack-timeline.md).
class RangedHitInstance extends DamageInstance:
	## The attacker this shot was fired for is [member HitInstance.attacker] —
	## promoted to the base class in #507 so the shared [CritRoll] can read its
	## board. Needed here at land time to re-check the target is still HOSTILE
	## to them, not just still allocated (a node can be captured by a third
	## party mid-volley).

	## Veto — no mutation at all, per the contract's "gate is a veto, not a
	## re-plan" — if the target is no longer allocated/hostile, or the firing
	## node ([member HitInstance.origin]) is no longer allocated. A mid-volley
	## cascade can deallocate either: the target (this volley's own overkill)
	## or the origin (a DIFFERENT attack, or this volley's own forced-dealloc
	## cascade, islanding the firing leaf). A veto marks [member
	## HitInstance.gated] so VFX can render the dud beat distinctly from a
	## hit that landed and fully mitigated to zero.
	##
	## The live offense read happens BEFORE `super`, deliberately: `super`'s
	## first act is [method CritRoll.apply], so the crit multiplies the number
	## this line just read rather than a resolve-time estimate that was about
	## to be thrown away (#507).
	func land_on(node: SkillNode) -> void:
		if not _passes_gate(node):
			gated = true
			return
		amount = RangedDamageFormula._read_offense(origin)
		super.land_on(node)


	func _passes_gate(node: SkillNode) -> bool:
		if origin == null or not is_instance_valid(origin) or not origin.is_allocated():
			return false
		if node == null or not is_instance_valid(node) or not node.is_allocated():
			return false
		return node.ownership_bit(attacker) == SkillNode.Ownership.HOSTILE
