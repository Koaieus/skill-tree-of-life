@tool
@abstract
class_name FoldReducer
extends IncidentReducer

## RED stub (#441): the template lands next commit.


func reduce(_incidents: Array[CastSpell], _cast: PropagationContext) -> CastSpell:
	return null


@abstract func _fold_damage(incidents: Array[CastSpell]) -> float
