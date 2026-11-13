@tool
class_name DetonateUse
extends LoadUse

## The load is spent at the hit as a blast: it adds to the cast's
## [member LoadBag.detonate_load], which each head carries as its
## [member HitInstance.hit_load] into go-off zero's disc ([DiscGoOff]), and
## plants no rider.


func spend(_row: AspectIntake, _status: StatusDef, amount: int, bag: LoadBag) -> void:
	bag.detonate_load += amount
