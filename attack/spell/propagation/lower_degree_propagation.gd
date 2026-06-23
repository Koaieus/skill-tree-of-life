@tool
class_name LowerDegreePropagation
extends SpellPropagation

## Leafblaster: propagates to every neighbour whose degree is strictly less
## than the current node's degree. Trickles outward toward the leaves; a
## central hub seeds first, then each subsequent hop only descends into
## "less-connected" territory. Caps out naturally at degree-1 leaves.
##
## With [member strict_less_than] off the rule becomes "≤ current" — useful
## for ridges of equal degree that you still want the spell to ride.

@export var strict_less_than: bool = true
@export var only_enemy: bool = true


func next_hops(state: CastSpell) -> Array[CastSpell]:
	if state.graph == null or state.current_node == null:
		return []
	var current_degree: int = state.graph.get_neighbours(state.current_node).size()
	var out: Array[CastSpell] = []
	for nb in state.graph.get_neighbours(state.current_node):
		if not revisit_visited and nb in state.visited:
			continue
		if only_enemy and nb.owned_by == state.caster:
			continue
		var nb_degree: int = state.graph.get_neighbours(nb).size()
		var ok := nb_degree < current_degree if strict_less_than else nb_degree <= current_degree
		if not ok:
			continue
		out.append(_propagate_to(nb, state))
	return out


func get_description() -> String:
	var op := "<" if strict_less_than else "≤"
	var scope := "enemy" if only_enemy else "any"
	return "Trickles to %s neighbours with degree %s current, up to %d hop%s." % [
		scope, op, max_hops, "" if max_hops == 1 else "s"]
