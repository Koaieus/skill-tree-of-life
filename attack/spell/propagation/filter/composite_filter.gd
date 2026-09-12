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


## Set-level composition. [constant Mode.AND] narrows SEQUENTIALLY — each
## child's [method PropagationFilter.narrow] runs over the previous child's
## survivors. For pairwise children that is exactly the AND of their
## [method PropagationFilter.allows], and it is also what gives a set-level
## child (e.g. [TopTiesFilter]) its meaning: "tied for highest *among what the
## earlier filters left*". Order therefore matters once a set-level child is
## in the array — put the cheap pairwise gates first.
##
## [constant Mode.OR] is the union of each child's narrowing of the FULL
## candidate set, in candidate order, so it stays the set-level reading of
## "any child admits it" without a child ever seeing a set another child
## already cut.
func narrow(
		from: SkillNode,
		candidates: Array[SkillNode],
		payload: CastSpell,
		ctx: PropagationContext) -> Array[SkillNode]:
	if children.is_empty():
		return candidates.duplicate()
	if mode == Mode.AND:
		# Duplicated, not aliased: every other exit from this method hands back
		# a fresh array (the empty-children path duplicates, the OR path builds
		# one), and a caller that got the SAME array it passed in from one
		# branch and a copy from another is the kind of asymmetry that bites
		# once someone mutates the result. An all-null `children` array is the
		# case that would otherwise return the input itself.
		var surviving: Array[SkillNode] = candidates.duplicate()
		for f in children:
			if f == null:
				continue
			surviving = f.narrow(from, surviving, payload, ctx)
			if surviving.is_empty():
				return surviving
		return surviving
	var admitted: Array[SkillNode] = []
	for f in children:
		if f == null:
			continue
		for n in f.narrow(from, candidates, payload, ctx):
			if not admitted.has(n):
				admitted.append(n)
	# Union in CANDIDATE order, not child order — the step's tie-break is
	# stable on scene order and must not depend on which child admitted first.
	var out: Array[SkillNode] = []
	for c in candidates:
		if admitted.has(c):
			out.append(c)
	return out


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
