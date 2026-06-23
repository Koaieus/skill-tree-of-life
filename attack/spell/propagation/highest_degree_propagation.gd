@tool
class_name HighestDegreePropagation
extends SpellPropagation

## Propagates to the [member take_count] neighbours with the highest live
## graph degree — the spell preferentially chains through hubs. Pairs well
## with low [member SpellPropagation.max_hops] (1..2) as a "find the
## backbone" probe.
##
## Degree is read from [method Graph.get_neighbours] live — if the runtime
## evolves so the resolver can mutate topology mid-resolve (e.g. nodes
## de-allocated by a prior on-hit effect during the same cast), the new
## degree is visible to subsequent hops. Today that doesn't happen: the
## resolver builds the full hit list before the VFX layer applies any
## damage, so degree is effectively a cast-time snapshot.

@export_range(1, 16) var take_count: int = 1
@export var only_enemy: bool = true


func next_hops(state: CastSpell) -> Array[CastSpell]:
	if state.graph == null or state.current_node == null:
		return []
	var candidates: Array[SkillNode] = []
	for nb in state.graph.get_neighbours(state.current_node):
		if not revisit_visited and nb in state.visited:
			continue
		if only_enemy and nb.owned_by == state.caster:
			continue
		candidates.append(nb)
	if candidates.is_empty():
		return []
	candidates.sort_custom(func(a: SkillNode, b: SkillNode) -> bool:
		return state.graph.get_neighbours(a).size() > state.graph.get_neighbours(b).size())
	var out: Array[CastSpell] = []
	var k: int = min(take_count, candidates.size())
	for i in k:
		out.append(_propagate_to(candidates[i], state))
	return out


func get_description() -> String:
	var scope := "enemy" if only_enemy else "any"
	return "Chains to the %d highest-degree %s neighbour%s, up to %d hop%s." % [
		take_count, scope, "" if take_count == 1 else "s",
		max_hops, "" if max_hops == 1 else "s"]
