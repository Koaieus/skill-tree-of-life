@tool
class_name PoolStatDef
extends StatDef

## A pool stat definition. The PoolStat itself IS the cap — modifiers target
## the pool stat id directly and the pipeline computes the maximum. `.current`
## is the separate ephemeral game state.

@export var min_value: int = 0
@export var is_growable: bool = false
@export var heal_on_max_increase: bool = true
@export var can_overflow: bool = false

## Growth formula (`PoolStat.grow()`):
##   new_max = round(old_max * growth_factor + growth_flat)
## Defaults to a no-op (factor 1, flat 0). Flat alone gives linear growth
## (XP: +5 per level); factor > 1 gives mild exponential curves.
@export var growth_flat: int = 0
@export var growth_factor: float = 1.0
