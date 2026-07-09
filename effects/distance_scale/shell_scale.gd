@tool
class_name ShellScale
extends DistanceScale

## Full strength at exactly `shell_distance`, a reduced band one step to either
## side, nothing elsewhere. The Halo's ring.
##
## Distances are compared with a tolerance so this works on a euclidean metric
## too, though hops are the intended pairing (the design doc's ring-shrink math
## is a BFS over the owned subgraph).

@export var shell_distance: float = 3.0
## Strength for nodes at `shell_distance ± 1` — the near-shell gradient.
@export var near_scale: float = 0.5
## Half-width of the "exactly at" band.
@export var tolerance: float = 0.001

func scale(distance: float, _max_distance: float) -> float:
	var delta: float = absf(distance - shell_distance)
	if delta <= tolerance:
		return 1.0
	if delta <= 1.0 + tolerance:
		return near_scale
	return 0.0
