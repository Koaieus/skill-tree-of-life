@tool
class_name NoStep
extends PropagationStep

## Returns no children — single-target spells. Equivalent to leaving
## [member PropagationConfig.step] null, but explicit so the .tres reads
## intentionally.


func step(_current: SkillNode, _payload: CastSpell, _candidates: Array[SkillNode],
		_config: PropagationConfig, _ctx: PropagationContext) -> Array[CastSpell]:
	return []


func get_description() -> String:
	return "Single target."
