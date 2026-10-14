@tool
class_name ExplosiveSpread
extends StatusSpread

## The explosive status's spread and the one owner of a charge's boom shape.
## Stub: filled in by the next commit.

@export var damage_per_charge: float = 2.0
@export var reach_per_radius: float = 3.0
@export var charge_exponent: float = 0.5


func radius_for(_node_radius: float, _charges: int) -> float:
	return 0.0
