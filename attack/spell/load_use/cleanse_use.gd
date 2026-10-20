@tool
class_name CleanseUse
extends LoadUse

## The load caps a cleanse: it becomes [member effect]'s cap for the concept's
## status ([member CleanseEffect.caps]). Every row pointing at the same
## [member effect] template shares ONE per-cast copy — found in the bag's
## riders by [member CleanseEffect.template] — so a cast lands one cleanse per
## landing whatever the number of rows. A concept with no status caps nothing.

## The shared [CleanseEffect] template; never mutated (a cast copies it).
@export var effect: CleanseEffect = null:
	set(value):
		effect = value
		emit_changed()


func spend(_row: AspectIntake, status: StatusDef, amount: int, bag: LoadBag) -> void:
	if effect == null or status == null:
		return
	var copy: CleanseEffect = null
	for rider in bag.riders:
		if rider is CleanseEffect and (rider as CleanseEffect).template == effect:
			copy = rider
			break
	if copy == null:
		copy = effect.for_cast()
		bag.riders.append(copy)
	copy.caps[status] = copy.caps.get(status, 0) + amount


## "Cleanses up to 20 Curse per hit; +3 per curse infused." — the innate cap
## through the same stacks fold the landing uses.
func describe(row: AspectIntake, board: StatBoard = null, read_node: SkillNode = null) -> String:
	var def := row.status()
	var label := def.display_name if not def.display_name.is_empty() else String(def.id)
	var slice := OnHitEffect.read_slice(read_node)
	var cap := def.stacks_per_hit_at(slice, float(row.innate)) if slice != null \
			else def.stacks_per_hit(board, float(row.innate))
	return "Cleanses up to %s %s per hit; %s." % [NumFmt.num(cap), label, row.ingest_line()]
