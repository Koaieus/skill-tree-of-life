@tool
class_name FlatDecay
extends StatusDecay

## A flat fade: [member per_tick] power removed every tick, floored at `0`
## (removed).

## Power removed per tick.
@export var per_tick: float = 1.0


func _init(p_per_tick: float = 1.0) -> void:
	per_tick = p_per_tick


func decayed(power: float, _row: NodeStatus = null) -> float:
	return maxf(power - per_tick, 0.0)


func describe() -> String:
	return "-%s per turn" % NumFmt.num(per_tick)
