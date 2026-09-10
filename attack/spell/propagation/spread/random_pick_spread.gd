@tool
class_name RandomPickSpread
extends PropagationSpread

## UNSHIPPED: no spell preset composes this spread yet — no production or test
## `.tres` references [RandomPickSpread]. Kept for a future stochastic-walk
## spell shape; delete if nothing needs it.
##
## Picks one eligible node uniformly at random. RNG is taken from
## [member CastSpell.rng] (threaded through every payload); null falls back to
## a fresh time-seeded RNG — fine for gameplay, useless for tests (which should
## inject a seeded RNG via [method SpellResolver.resolve]).


func select(
		_current: SkillNode,
		eligible: Array[SkillNode],
		payload: CastSpell,
		_ctx: PropagationContext) -> Array[PropagationPick]:
	if eligible.is_empty():
		return []
	var rng := payload.rng
	if rng == null:
		rng = RandomNumberGenerator.new()
	var pick: SkillNode = eligible[rng.randi_range(0, eligible.size() - 1)]
	return [PropagationPick.to(pick)]


func get_description() -> String:
	return "Random-walks one neighbour per hop."
