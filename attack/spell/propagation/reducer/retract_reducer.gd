@tool
class_name RetractReducer
extends MaxDamageReducer

## The stock merge (one landing per node per wave), plus [RetractSpread]'s
## guard: a tendril hopping in place ([constant RetractFront.Phase.WAIT]) and
## a return arriving at the same node on the same wave — the in-place one
## continues and the returns are cancelled, so nothing moves on their edges.
## The wave timing never produces the meeting; this keeps the merge from
## mixing phases if it ever does.

## The [RetractFront] whose phase this reads.
@export var front_id: StringName = RetractFront.ID


func reduce(incidents: Array[CastSpell], cast: PropagationContext) -> CastSpell:
	var waiting: Array[CastSpell] = []
	for inc in incidents:
		var st := RetractFront.state_of(inc, front_id)
		if st != null and st.phase == RetractFront.Phase.WAIT:
			waiting.append(inc)
	return super.reduce(waiting if not waiting.is_empty() else incidents, cast)


func get_description() -> String:
	return "Converging tendrils land once; one waiting in place outlasts an incoming return."
