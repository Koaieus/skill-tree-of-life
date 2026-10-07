class_name BleedingStatus
extends StatusDef

## Bleeding: an open wound that pays flat HP each turn and grows when the
## host works. STUB — red acceptance first.

@export_range(1.0, 4.0) var exert_growth: float = 2.0
@export var bleed_rate: float = 0.5


func _on_tick(_host, _before: float, _after: float) -> void:
	pass


func _on_exerted(_host) -> void:
	pass
