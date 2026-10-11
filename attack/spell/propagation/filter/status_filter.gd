@tool
class_name StatusFilter
extends PropagationFilter

## Admits a candidate carrying at least [member min_stacks] of ANY status in
## [member statuses] — "follow the infection". Reads through
## [method LandingContext.stacks_of], so a node this cast already cured on an
## earlier wave reads clean while the live node keeps its stacks. Compose with
## [OwnerFilter] through [CompositeFilter] (AND) to restrict whose nodes.

## Statuses that make a candidate eligible; empty admits nothing.
@export var statuses: Array[StatusDef] = []

## Stacks of a listed status needed to qualify (tentative, easy to change).
@export_range(0.0, 100.0, 0.5, "or_greater") var min_stacks: float = 1.0


func allows(to: SkillNode, lctx: LandingContext) -> bool:
	if to == null:
		return false
	for def in statuses:
		if def != null and lctx.stacks_of(to, def.id) >= min_stacks:
			return true
	return false


func get_description() -> String:
	var names: Array[String] = []
	for def in statuses:
		if def != null:
			names.append(def.display_name if def.display_name != "" else String(def.id))
	if names.is_empty():
		return ""
	return "Only nodes carrying %s." % " or ".join(names)
