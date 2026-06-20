@tool
class_name PoolStatDef
extends StatDef

## A pool stat definition. The PoolStat itself IS the cap — modifiers target
## the pool stat id directly and the pipeline computes the maximum. `.current`
## is the separate ephemeral game state.

@export var min_value: int = 0
@export var heal_on_max_increase: bool = true


@export_group('Growth')

## If on: PoolStat calls `grow()` when `replenished`, using formula below
@export var is_growable: bool = false  
## Growth formula (`PoolStat.grow()`):
##   new_max = round(old_max * growth_factor + growth_flat)
## Defaults to a no-op (factor 1, flat 0). Flat alone gives linear growth
## (XP: +5 per level); factor > 1 gives mild exponential curves.
@export var growth_flat: int = 0
@export var growth_factor: float = 1.0
## If on, `grow()` subtracts the previous max from `current` after bumping the
## cap — XP-style: pool resets toward 0 for the next level. Off = HP-style:
## cap grows, current stays put (the pool effectively heals).
@export var deduct_old_max: bool = true
