@tool
@abstract
class_name PropagationStep
extends Resource

## Mints the outgoing [CastSpell] copies for one node's expansion, given the
## already-filtered candidate set. Payload mutations (damage scaling,
## hops--) happen here.
##
## Helpers on the base ([method _propagate_to]) cover the 95% case: copy
## fields, decrement hops, advance hop_index, scale damage. Custom steps
## override [method step] entirely.


@abstract func step(
		current_node: SkillNode,
		payload: CastSpell,
		candidates: Array[SkillNode],
		config: PropagationConfig,
		ctx: PropagationContext) -> Array[CastSpell]


func get_description() -> String:
	return ""


## Mint a fresh CastSpell propagated from [param payload] into [param to].
## Damage is multiplied by [member PropagationConfig.damage_multiplier_per_hop];
## hops_remaining decrements; hop_index advances. Subclasses with bespoke
## payload mutations should call this then mutate, or skip it entirely.
func _propagate_to(to: SkillNode, payload: CastSpell, config: PropagationConfig) -> CastSpell:
	var next := CastSpell.new()
	next.seed_node = payload.seed_node
	next.current_node = to
	next.predecessor = payload.current_node
	next.source = payload.source
	next.damage = payload.damage * config.damage_multiplier_per_hop
	next.hops_remaining = payload.hops_remaining - 1
	next.hop_index = payload.hop_index + 1
	next.visited = payload.visited.duplicate()
	next.visited.append(to)
	next.caster = payload.caster
	next.graph = payload.graph
	next.rng = payload.rng
	return next
