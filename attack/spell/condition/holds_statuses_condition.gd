@tool
class_name HoldsStatusesCondition
extends LandingCondition

@export var statuses: Array[StatusDef] = []


func evaluate(_lctx: LandingContext) -> bool:
	return false
