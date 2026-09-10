@tool
class_name FanAllSpread
extends PropagationSpread

## One pick per eligible node, full share each. The default spread for
## Lightning / Crunch / Flood / Resonator — "spell goes everywhere the filter
## allowed."


func select(
		_current: SkillNode,
		eligible: Array[SkillNode],
		_payload: CastSpell,
		_ctx: PropagationContext) -> Array[PropagationPick]:
	var out: Array[PropagationPick] = []
	for nb in eligible:
		out.append(PropagationPick.to(nb))
	return out


func get_description() -> String:
	return "Fans to every eligible neighbour."
