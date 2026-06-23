@tool
class_name RandomWalkPropagation
extends SpellPropagation

## True random walk — picks ONE neighbour at random each step and propagates
## there. Friends, foes, the caster's own nodes — anything connected is fair
## game. The seed-side hop count caps the walk length.
##
## Seeding: the RNG is threaded through [member CastSpell.rng]. Pass one via
## [method SpellResolver.resolve]'s `rng` argument to get reproducible casts
## (tests, recorded replays). If [code]state.rng[/code] is null this falls
## back to a fresh [RandomNumberGenerator] with the default (time-derived)
## seed — fine for gameplay, useless for tests.
##
## Termination: if the only remaining neighbour candidates were already
## visited and [member SpellPropagation.revisit_visited] is false, the walk
## stops short of [member SpellPropagation.max_hops]. Set revisit_visited =
## true if you want a "drunk walk" that can loop.


func next_hops(state: CastSpell) -> Array[CastSpell]:
	if state.graph == null or state.current_node == null:
		return []
	var candidates: Array[SkillNode] = []
	for nb in state.graph.get_neighbours(state.current_node):
		if not revisit_visited and nb in state.visited:
			continue
		candidates.append(nb)
	if candidates.is_empty():
		return []
	var rng := state.rng
	if rng == null:
		rng = RandomNumberGenerator.new()
	var pick: SkillNode = candidates[rng.randi_range(0, candidates.size() - 1)]
	return [_propagate_to(pick, state)]


func get_description() -> String:
	return "Random walk through any neighbour, up to %d hop%s." % [
		max_hops, "" if max_hops == 1 else "s"]
