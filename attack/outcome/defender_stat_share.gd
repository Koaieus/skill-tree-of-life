@tool
class_name DefenderStatShare
extends StackTerm

## Stub.

@export var stat_id: StringName = &"armor"
@export_range(0, 4) var ratio: float = 0.25
@export_range(1, 8, 1, "or_greater") var unlock_level: int = 1
