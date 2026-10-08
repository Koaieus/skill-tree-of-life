@tool
class_name RampDecay
extends StatusDecay

## A ramping fade: the first rest tick removes [member start], each further one
## [member step] more — `start + step × row.decay_step`, floored at `0`
## (removed). The ramp's position lives on the row
## ([member NodeStatus.decay_step]); an exertion resets it, so a host that keeps
## acting keeps its status near full.

## Power removed by the first rest tick.
@export var start: float = 1.0
## Extra power removed by each further rest tick.
@export var step: float = 1.0


func _init(p_start: float = 1.0, p_step: float = 1.0) -> void:
	start = p_start
	step = p_step


func decayed(power: float, row: NodeStatus = null) -> float:
	var at := row.decay_step if row != null else 0
	return maxf(power - (start + step * at), 0.0)


func describe() -> String:
	return "-%s per turn, +%s each turn rested" % [NumFmt.num(start), NumFmt.num(step)]
