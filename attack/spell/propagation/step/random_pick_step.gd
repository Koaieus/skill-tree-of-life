@tool
class_name RandomPickStep
extends PropagationStep

## UNSHIPPED: no spell preset composes this step yet — no production or test
## `.tres` references [RandomPickStep]. Kept for a future stochastic-walk
## spell shape; delete if nothing needs it.
##
## Picks one candidate uniformly at random and propagates there. RNG is
## taken from [member CastSpell.rng] (threaded through every payload); null
## falls back to a fresh time-seeded RNG — fine for gameplay, useless for
## tests (which should inject a seeded RNG via [method SpellResolver.resolve]).


func step(
		_current: SkillNode,
		payload: CastSpell,
		candidates: Array[SkillNode],
		config: PropagationConfig,
		_ctx: PropagationContext) -> Array[CastSpell]:
	if candidates.is_empty():
		return []
	var rng := payload.rng
	if rng == null:
		rng = RandomNumberGenerator.new()
	var pick: SkillNode = candidates[rng.randi_range(0, candidates.size() - 1)]
	return [_propagate_to(pick, payload, config)]


func get_description() -> String:
	return "Random-walks one neighbour per hop."
