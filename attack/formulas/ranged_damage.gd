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
## first). The ramp is authored by rank instead: RangedAttackPlan.resolve()
## ranks reaching leaves by distance to target and stamps `arrival_time`
## from the constants below. `compute()` leaves it at the HitInstance
## default (0.0) — it is filled in exactly once, by the caller that knows
## the shot's rank.

## Constant per-shot flight duration (s) — every shot takes the same time to
## land regardless of distance. The fiction is the arc: a point-blank shot
## is lobbed nearly straight up, a distant one goes nearly flat, and both
## take about the same time to come down. This is what makes arrival order
## == firing order == distance order UNCONDITIONALLY (a distance-scaled
## flight speed could invert it). Also the animation's per-shot speed is now
## derived (`distance / FLIGHT_TIME`) rather than driving the schedule.
const FLIGHT_TIME: float = 0.35

## Total span (s) the launch ramp covers, nearest-to-target leaf to
## furthest-reaching leaf — fixed regardless of shot count, so a 4-shot and
## a 100-shot volley take the same wall time and stay readable rather than
## crawling. Verified against ArrowVolleyCoordinator.MIN_FLIGHT_FRACTION's
## clamp in test_arrow_volley_coordinator.gd — see the issue's "Watch" note.
const TOTAL_STAGGER: float = 0.6

## Windup before the first release. 0.0 for now, per the issue's settled
## design — authored in from the start so a draw phase can be turned on
## without re-deriving the schedule.
const DRAW_TIME: float = 0.0

static func compute(_attacker: Entity, firing_node: SkillNode, target: SkillNode) -> DamageInstance:
	var hit := DamageInstance.new()
	hit.type = DamageInstance.Type.PHYSICAL
	hit.target = target
	hit.origin = firing_node
	if firing_node != null:
		hit.amount = float(firing_node.get_local_value(&"ranged_damage"))
	return hit
