@tool
class_name CyclicPoolStatDef
extends PoolStatDef

## A pool that cycles: filling to the cap does NOT grow it and does NOT leave
## `current` parked at the cap — it carries the overflow into the next cycle and
## starts climbing again from `min + excess`. The cap is a recurring *threshold*,
## not a ceiling the gauge rests against.
##
## Used by `initiative`: the cap is the per-entity action threshold (default 100).
## Each TurnManager tick replenishes by `initiative_speed`; crossing the cap fires
## `replenished` (entities listen and join the `ready_to_act` group) and carries the
## overshoot forward — so the "deduct 100 on act" is implicit and entities that
## overshot more keep that lead into the next race.
##
## This is GrowablePoolStatDef's OVERFLOW post-grow behaviour minus the growth;
## Growable can't be reused because its `on_pool_filled` bails when the cap delta
## is zero (`if delta <= 0.0: return`), which is exactly the no-grow case here.


func on_pool_filled(stat: PoolStat, excess: float) -> void:
	# `current` is sitting at the cap (the crossing consumed it); restart the
	# cycle at just the carried overflow.
	stat.set_current(float(stat._min_value()) + excess)
