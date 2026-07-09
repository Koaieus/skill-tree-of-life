@tool
class_name ProportionalScale
extends DistanceScale

## Scales linearly with raw distance and ignores the reach bound entirely:
## `scale = distance * per_unit`. Unbounded by construction.
##
## The Ninja's `armor -1` per hop, and both of the Serpent's components. The
## source node itself lands at 0, i.e. unaffected — an aura that pivots on
## distance-from-core shouldn't buff the core.
##
## Pair with `reach = null` (flood the whole scope). Pairing it with a bounded
## reach is the trap: nodes past the bound escape the effect entirely, which
## inverts a *penalty* aura into a reward for standing far away.

## Multiplier per unit of distance (per hop, or per pixel).
@export var per_unit: float = 1.0

func scale(distance: float, _max_distance: float) -> float:
	return distance * per_unit
