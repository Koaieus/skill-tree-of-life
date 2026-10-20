@tool
class_name HoldsStatusesCondition
extends LandingCondition

## True iff the landed spot holds EVERY listed status — more than 0 stacks,
## counting the node's rows and, on a core node, its owner's entity rows
## ([method LandingContext.spot_stacks_of]), read on the world the walk reads.
## An empty list is never true.

## The statuses the spot must all hold.
@export var statuses: Array[StatusDef] = []


func evaluate(lctx: LandingContext) -> bool:
	if lctx == null or lctx.node == null or statuses.is_empty():
		return false
	for def in statuses:
		if def == null or lctx.spot_stacks_of(lctx.node, def.id) <= 0.0:
			return false
	return true


func get_description() -> String:
	var names: Array[String] = []
	for def in statuses:
		if def != null:
			names.append((def.display_name if def.display_name != "" else String(def.id)).to_lower())
	return "on a node holding %s" % " and ".join(names) if not names.is_empty() else ""
