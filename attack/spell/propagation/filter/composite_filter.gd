@tool
class_name CompositeFilter
extends PropagationFilter

## AND / OR combine children. Mirrors the composable pattern [RangeFinder]
## uses — most real spells need MaxVisits + Owner + maybe one shape filter.

enum Mode { AND, OR }

@export var mode: Mode = Mode.AND
@export var children: Array[PropagationFilter] = []


func allows(from: SkillNode, to: SkillNode, payload: CastSpell, ctx: PropagationContext) -> bool:
	if children.is_empty():
		return true
	match mode:
		Mode.AND:
			for f in children:
				if f != null and not f.allows(from, to, payload, ctx):
					return false
			return true
		Mode.OR:
			for f in children:
				if f != null and f.allows(from, to, payload, ctx):
					return true
			return false
	return true


func get_description() -> String:
	var parts: PackedStringArray = []
	for f in children:
		if f == null:
			continue
		var d := f.get_description()
		if d != "":
			parts.append(d)
	if parts.is_empty():
		return ""
	var sep := " and " if mode == Mode.AND else " or "
	return sep.join(parts)
