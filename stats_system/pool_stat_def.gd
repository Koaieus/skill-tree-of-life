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

## Growth formula (`PoolStat.grow()`):
##   new_max = round(old_max * growth_factor + growth_flat)
## Defaults to a no-op (factor 1, flat 0). Flat alone gives linear growth
## (XP: +5 per level); add a >1 factor for mild exponential curves
## (e.g. flat 2, factor 1.2). Only consulted when something calls grow().
@export var growth_flat: int = 0
@export var growth_factor: float = 1.0
