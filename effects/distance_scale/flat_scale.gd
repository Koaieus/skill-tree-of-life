@tool
class_name FlatScale
extends DistanceScale

## Uniform strength everywhere inside reach. Bulwark's fortress zone: you are
## either in the aura or you aren't. The default when no scale is authored.

func scale(_distance: float, _max_distance: float) -> float:
	return 1.0
