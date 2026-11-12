@tool
class_name CatalystStatus
extends StatusDef

## Stub (#1801 C, red first).

@export_range(1, 10, 1, "or_greater") var ratio_in: int = 1
@export_range(1, 10, 1, "or_greater") var ratio_out: int = 1
@export var cap_k_times_t: bool = true


static func converted(_store: int, _landing: Dictionary) -> Dictionary:
	return {}


func convert(_host, _landing: Dictionary) -> Dictionary:
	return {}
