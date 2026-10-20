@tool
class_name DetonateUse
extends LoadUse

## The load is spent at the hit as a blast ([DetonateEffect]): it adds to the
## cast's [member LoadBag.detonate_load] and plants no rider.


func spend(_row: AspectIntake, _status: StatusDef, amount: int, bag: LoadBag) -> void:
	bag.detonate_load += amount
