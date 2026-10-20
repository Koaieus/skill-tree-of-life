@tool
class_name PhaseCondition
extends LandingCondition

## True when the landing's [RetractFront] tendril is in [member phase] — the
## gate splitting Lodestone's outbound riders from its return haul. False on a
## payload carrying no such front.

@export var phase: RetractFront.Phase = RetractFront.Phase.OUT

## The [RetractFront] whose phase this reads.
@export var front_id: StringName = RetractFront.ID


func evaluate(lctx: LandingContext) -> bool:
	var st := RetractFront.state_of(lctx.payload, front_id)
	return st != null and st.phase == phase


func get_description() -> String:
	return "on the way %s" % ["out", "in place", "back"][phase]
