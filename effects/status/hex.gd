@tool
class_name HexStatus
extends StatusDef

## Resistance lost per stack.
@export_range(0.0, 1.0, 0.01, "or_greater") var resist_per_stack: float = 0.1
