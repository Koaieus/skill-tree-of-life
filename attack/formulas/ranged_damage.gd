class_name RangedDamageFormula

## Pure-function damage formula for a single ranged shot. One hit per firing
## position; the resolver loops positions and accumulates DamageInstances.
##
## Per-shot model deliberately: lets future flat armour reduce each impact
## instead of one big number, and supports staggered VFX hits.
##
## Formula: `floor(DEX / DEX_DIVISOR) + BASE_DAMAGE`. PHYSICAL.
##
## DEX is read node-locally off [param firing_node] (wielder baseline merged
## with node-local addons, e.g. a "sniper nest" granting local DEX) — see
## `.claude/rules/graph.md` and #171.

const BASE_DAMAGE: float = 1.0
const DEX_DIVISOR: float = 10.0


static func compute(_attacker: Entity, firing_node: SkillNode, target: SkillNode) -> DamageInstance:
	var hit := DamageInstance.new()
	hit.type = DamageInstance.Type.PHYSICAL
	hit.target = target
	hit.origin = firing_node
	var dex: float = 0.0
	if firing_node != null:
		dex = float(firing_node.get_local_value(&"dexterity"))
	hit.amount = floor(dex / DEX_DIVISOR) + BASE_DAMAGE
	return hit
