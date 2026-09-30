class_name GateFlipInstance
extends HitInstance

## STUB (#1209) — red-first seam.

var gates: Array[Gate] = []


func _init() -> void:
	kind = Kind.GATE_FLIP


func land_on(_node: NodeCombat, _world: CombatWorld) -> void:
	pass
