class_name RangedDamageFormula

## Pure-function damage formula for a single ranged shot. One hit per firing
## position; the resolver loops positions and accumulates DamageInstances.
##
## Per-shot model deliberately: lets future flat armour reduce each impact
## instead of one big number, and supports staggered VFX hits.
##
## Reads `ranged_damage` from the firing node's local stat board — the
## entity board intrinsic formula (`floor(DEX / 10.0)`) plus any node-local
## addons contribute to the value, so the UI and resolver stay dumb.

## Flat flight speed (px/s) every shot travels at. No per-node/per-entity
## stat backs this yet — same "constant for now" stance ArrowVolleyCoordinator
## takes with its flight_time export.
const PROJECTILE_SPEED: float = 900.0

## Per-shot launch offset (s) applied by RangedAttackPlan.resolve so a hit's
## recorded [member DamageInstance.arrival_time] is the FULL time from volley
## start (t=0) to impact: [code]index * LAUNCH_STAGGER + distance /
## PROJECTILE_SPEED[/code]. Single home for the stagger schedule —
## ArrowVolleyCoordinator's [code]stagger_per_shot[/code] export defaults to
## this so VFX launches and the recorded timeline can't drift (#479/#481
## lesson applied at the data layer: a replay reconstructs the exact volley
## from [code]outcome.hits[/code] alone).
const LAUNCH_STAGGER: float = 0.2

static func compute(_attacker: Entity, firing_node: SkillNode, target: SkillNode) -> DamageInstance:
	var hit := DamageInstance.new()
	hit.type = DamageInstance.Type.PHYSICAL
	hit.target = target
	hit.origin = firing_node
	if firing_node != null:
		hit.amount = float(firing_node.get_local_value(&"ranged_damage"))
	if firing_node != null and target != null:
		var distance := firing_node.global_position.distance_to(target.global_position)
		hit.arrival_time = distance / PROJECTILE_SPEED
	return hit
