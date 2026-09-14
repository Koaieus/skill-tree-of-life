class_name BlindnessStatus
extends StatusDef

## Blindness (#873) — stub seam; behaviour lands next commit.

## The multiplier on `vision_range` / `sensor_range` at full power.
@export var blind_factor: float = 0.5


class BlindModifier:
	extends StatModifier
