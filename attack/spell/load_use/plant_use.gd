@tool
class_name PlantUse
extends LoadUse

## The load lands as the concept's status rider: one [ApplyStatusEffect] at
## `power = load`, folding this use's [member stack_terms]. A concept with no
## status plants nothing.

## Extra-stack terms the rider carries ([member ApplyStatusEffect.stack_terms]),
## each a [StackTerm] read at land against the landing world. A spell that also
## scales its damage by the same term shares the SubResource with its
## [AddStackTermDamageEffect]: one formula, two readers.
@export var stack_terms: Array[StackTerm] = []:
	set(value):
		stack_terms = value
		emit_changed()
## The rider's [member ApplyStatusEffect.power_from]: the id of a
## [CarriedScalar] whose value it lands instead of the load, where the payload
## carries one. Empty = the load at every landing.
@export var power_from: StringName = &"":
	set(value):
		power_from = value
		emit_changed()


func spend(_row: AspectIntake, status: StatusDef, amount: int, bag: LoadBag) -> void:
	if status == null:
		return
	var rider := ApplyStatusEffect.new()
	rider.def = status
	rider.power = float(amount)
	rider.stack_terms = stack_terms.duplicate()
	rider.power_from = power_from
	bag.riders.append(rider)
