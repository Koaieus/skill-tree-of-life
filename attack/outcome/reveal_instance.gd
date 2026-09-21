class_name RevealInstance
extends HitInstance

## A scout arrow's landing (#1033): no HP, no status — [member amount] is a
## vision RADIUS in world units, [member attacker] the firer whose vision group
## gains it, [member target] the node it lands on. Stub: `land_on` pending.


func _init() -> void:
	kind = Kind.REVEAL


func land_on(_node: NodeCombat, _world: CombatWorld) -> void:
	pass
