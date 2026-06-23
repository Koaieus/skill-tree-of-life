@tool
class_name AllNeighboursPropagation
extends SpellPropagation

## BFS fan-out: propagates to every adjacent node not yet visited. Drives
## Lightning Bolt (×0.5 multiplier), Crunch Bolt (×2 multiplier, seed at
## 1/4), and Flood (×1 multiplier on a large [member SpellPropagation.max_hops]).
## Fork-friendly by construction — every neighbour gets its own state.
##
## [member only_enemy] filters to nodes NOT owned by the caster — the
## typical "spell doesn't hit my own stuff" rule. Toggle off for friendly-
## fire variants or buff-spell shapes.

@export var only_enemy: bool = true


func next_hops(state: CastSpell) -> Array[CastSpell]:
	if state.graph == null or state.current_node == null:
		return []
	var out: Array[CastSpell] = []
	for nb in state.graph.get_neighbours(state.current_node):
		if not revisit_visited and nb in state.visited:
			continue
		if only_enemy and nb.owned_by == state.caster:
			continue
		out.append(_propagate_to(nb, state))
	return out


func get_description() -> String:
	var hops := "%d hop%s" % [max_hops, "" if max_hops == 1 else "s"]
	var falloff := "" if is_equal_approx(damage_multiplier_per_hop, 1.0) else " (×%.2g per hop)" % damage_multiplier_per_hop
	var scope := "enemy neighbours" if only_enemy else "all neighbours"
	return "Chains to %s, up to %s%s." % [scope, hops, falloff]
