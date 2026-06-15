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


func next_hops(state: SpellState) -> Array[SpellState]:
	if state.graph == null or state.current_node == null:
		return []
	var out: Array[SpellState] = []
	for nb in state.graph.get_neighbours(state.current_node):
		if not revisit_visited and nb in state.visited:
			continue
		if only_enemy and nb.owned_by == state.caster:
			continue
		out.append(_propagate_to(nb, state))
	return out
