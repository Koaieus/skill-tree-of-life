@tool
class_name FrozenAdmits
extends Admits

## Ice's answers on a Frozen node (stub).

@export_range(0.0, 1.0, 0.01) var break_fraction_max_hp: float = 0.10
@export_range(0, 4, 1, "or_greater") var break_channels: int = 2
@export_range(0.0, 0.2, 0.001, "or_greater") var shatter_fraction_per_stack: float = 0.01
@export_range(0.0, 1.0, 0.05) var shatter_spend_fraction: float = 1.0
@export_range(0.0, 1.0, 0.01, "or_greater") var vertex_bonus_per_excess: float = 0.10
