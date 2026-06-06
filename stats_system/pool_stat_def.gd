@tool
class_name PoolStatDef
extends StatDef

## A pool stat (current + max). The `max` is itself a first-class StatDef in
## the registry, targeted via `max_id` — so node modifiers reach it through
## the normal stat_id routing (no sub-stat syntax). See design doc.

@export var max_id: StringName = &""
@export var min_value: int = 0
@export var is_growable: bool = false
@export var heal_on_max_increase: bool = true
@export var can_overflow: bool = false
# growth_formula: TBD (Callable / GrowthCurve resource)
