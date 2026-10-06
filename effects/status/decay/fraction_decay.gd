class_name FractionDecay
extends StatusDecay

## A proportional fade on a whole stack count (ADR 0032): [member fraction] of
## the power is REMOVED every tick and the floor is KEPT — `⌊S · (1 − f)⌋`, so
## `0.5` from 10 steps 5 → 2 → 1 → 0. It always reaches 0. A float's noise on a
## whole (`5 × 0.8 = 4.0000…01` or `3.9999…`) counts as that whole.

## The fraction of the power REMOVED per tick (`0.2` keeps four fifths).
@export_range(0.0, 1.0, 0.01) var fraction: float = 0.5


func _init(p_fraction: float = 0.5) -> void:
	fraction = p_fraction


func decayed(power: float, _row: NodeStatus = null) -> float:
	var after := power * (1.0 - fraction)
	var kept := roundf(after) if is_equal_approx(after, roundf(after)) else floorf(after)
	return kept if kept >= 1.0 else 0.0


func describe() -> String:
	return "-%s per turn" % NumFmt.num(fraction)
