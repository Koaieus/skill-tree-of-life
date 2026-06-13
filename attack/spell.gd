class_name Spell
extends Resource

@export var name: String
@export_multiline var description: String

@export var mana_cost: int = 0


func validate(plan: MagicAttackPlan) -> Array[String]:
	return []


func _to_string() -> String:
	return "<Spell %s (%d mana)>" % [name, mana_cost]
