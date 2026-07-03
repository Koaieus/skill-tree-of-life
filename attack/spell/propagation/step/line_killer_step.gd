@tool
class_name LineKillerStep
extends PropagationStep

## Single-path walker for "The Line Killer" spell: picks one eligible neighbour
## at random, then:
##   - degree == 2: adds 1 to damage and continues (builds payload for the
##     "long string" payoff)
##   - degree > 2: squares the incoming damage and stops (the terminal
##     burst — hops_remaining = 0 prevents further propagation).
##
## Designed to be paired with a CompositeFilter that enforces degree >= 2
## and enemy ownership. The seed target itself should have degree >= 3
## (set via [member SpellDef.min_degree]).


func step(
		current_node: SkillNode,
		payload: CastSpell,
		candidates: Array[SkillNode],
		config: PropagationConfig,
		ctx: PropagationContext) -> Array[CastSpell]:
	if candidates.is_empty() or ctx.graph == null:
		return []
	var rng := payload.rng
	if rng == null:
		rng = RandomNumberGenerator.new()
	# todo: should propagate to ALL degree≥2 nodes
	var pick: SkillNode = candidates[rng.randi_range(0, candidates.size() - 1)]
	var node_degree = pick.owned_by.navigator.get_degree(pick) # this is the only real degree that matters: graph degree
	# Todo rewrite using proper propagation, first design tests
	var deg := ctx.graph.get_neighbours(pick).size()
	payload.damage += 1
	if deg == 2:
		var next := _propagate_to(pick, payload, config)
		#next.damage = payload.damage + 1.0
		return [next]
	var next := _propagate_to(pick, payload, config)
	next.damage = payload.damage * payload.damage
	next.hops_remaining = 0
	return [next]


func get_description() -> String:
	return "Walks a single path — +1 damage per degree-2 hop, squares at degree >2."
