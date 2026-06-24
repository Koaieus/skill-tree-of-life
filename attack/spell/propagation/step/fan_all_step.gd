@tool
class_name FanAllStep
extends PropagationStep

## Mints one copy per candidate, each with the per-hop damage multiplier
## applied. The default step for Lightning / Crunch / Flood / Resonator —
## "spell goes everywhere the filter allowed."


func step(
		_current: SkillNode,
		payload: CastSpell,
		candidates: Array[SkillNode],
		config: PropagationConfig,
		_ctx: PropagationContext) -> Array[CastSpell]:
	var out: Array[CastSpell] = []
	for nb in candidates:
		out.append(_propagate_to(nb, payload, config))
	return out


func get_description() -> String:
	return "Fans to every eligible neighbour."
