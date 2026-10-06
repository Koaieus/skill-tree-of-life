class_name WeaknessStatus
extends StatusDef

## STUB — the red test's seam; the real body lands next.

const STAT_IDS: Array[StringName] = [&"ranged_damage", &"blade_damage", &"spell_damage"]

@export var half_depth: float = 5.0
@export var floor_factor: float = 0.1


class WeaknessModifier:
	extends StatModifier


func factor_for(_power: float) -> float:
	return 1.0
