@tool
class_name FirstReducer
extends FoldReducer

## Takes the first-arrived incident verbatim, ignoring later arrivals at
## the same node in the same wave. Deterministic (the first incident is
## scene-order stable through the BFS queue). The implicit default when
## [member PropagationConfig.reducer] is null.


func _fold_damage(incidents: Array[CastSpell]) -> float:
	return incidents[0].damage


func get_description() -> String:
	return "First-arrived wins on overlap."
