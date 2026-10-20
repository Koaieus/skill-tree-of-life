@tool
class_name PhaseCondition
extends LandingCondition

@export var phase: RetractFront.Phase = RetractFront.Phase.OUT


func evaluate(_lctx: LandingContext) -> bool:
	return false
