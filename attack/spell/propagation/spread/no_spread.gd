@tool
class_name NoSpread
extends PropagationSpread

## Selects nothing — single-target spells. Equivalent to leaving
## [member PropagationConfig.spread] null, but explicit so the .tres reads
## intentionally.


func select(_eligible: Array[SkillNode], _lctx: LandingContext) -> Array[PropagationPick]:
	return []


func get_description() -> String:
	return "Single target."
