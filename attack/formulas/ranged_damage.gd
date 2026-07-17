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

static func compute(_attacker: Entity, firing_node: SkillNode, target: SkillNode) -> DamageInstance:
	var hit := DamageInstance.new()
	hit.type = DamageInstance.Type.PHYSICAL
	hit.target = target
	hit.origin = firing_node
	if firing_node != null:
		hit.amount = float(firing_node.get_local_value(&"ranged_damage"))
	return hit
