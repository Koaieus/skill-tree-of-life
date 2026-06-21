@tool
class_name StandardPoolStatDef
extends PoolStatDef

## A fixed-cap pool (HP, mana, action points, deallocation points, …).
## The cap moves only via the modifier pipeline; this class adds the
## optional "heal current to follow a cap rise" behaviour.

## When the modifier-driven cap rises, bump `current` by the same delta so the
## relative fill stays the same. Off = a raw cap raise leaves current put
## (the bar looks emptier).
@export var heal_on_max_increase: bool = true


func on_max_increased(stat: PoolStat, delta: float) -> void:
	if heal_on_max_increase:
		stat.set_current(stat.current + delta)
