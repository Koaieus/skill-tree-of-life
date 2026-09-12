@tool
class_name RandomPickSpread
extends PropagationSpread

## UNSHIPPED as content: no spell preset composes this spread — no `.tres`
## references [RandomPickSpread]. [b]It is not dead code, though:[/b]
## `test/unit/attack/test_attack_determinism.gd` uses it as the fixture that
## PROVES seeds matter (a resolve under two seeds must diverge), and
## `test_propagation.gd` pins its seeded pick. Deleting it would quietly
## weaken the determinism suite, so don't — retire the fixture first.
##
## Picks one eligible node uniformly at random. RNG is taken from
## [member CastSpell.rng] (threaded through every payload).
##
## [b]The null-RNG fallback below is a KNOWN determinism hazard[/b], tracked as
## one of the three named exceptions in `docs/domain/multiplayer-sync-model.md`
## ("Combat is nearly RNG-free — but not entirely"). A fresh time-seeded RNG is
## something a peer cannot reproduce, and under the host-authoritative model
## (`.claude/rules/multiplayer-sync.md`) a mirror must never roll its own. It
## is harmless only while nothing ships this spread. Inject a seeded RNG via
## [method SpellResolver.resolve] before any spell composes it.


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
