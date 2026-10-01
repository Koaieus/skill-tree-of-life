class_name FractionDecay
extends StatusDecay

## A proportional fade: [member fraction] of the power is REMOVED every tick
## (`0.5` halves), and the tail is cut — removed — on the tick whose
## post-decay value is below 1.

## The fraction of the power REMOVED per tick (`0.2` keeps four fifths).
@export_range(0.0, 1.0, 0.01) var fraction: float = 0.5


func _init(p_fraction: float = 0.5) -> void:
	fraction = p_fraction


func decayed(power: float) -> float:
	var after := power * (1.0 - fraction)
	return after if after >= 1.0 else 0.0


func describe() -> String:
	return "-%s per turn" % NumFmt.num(fraction)
