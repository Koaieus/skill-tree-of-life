@tool
class_name NoSpread
extends PropagationSpread

## Selects nothing — single-target spells. Equivalent to leaving
## [member PropagationConfig.spread] null, but explicit so the .tres reads
## intentionally.


func select(_current: SkillNode, _eligible: Array[SkillNode], _payload: CastSpell,
		_ctx: PropagationContext) -> Array[PropagationPick]:
	return []


func get_description() -> String:
	return "Single target."
