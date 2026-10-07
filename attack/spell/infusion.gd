class_name Infusion
extends RefCounted


static func innate(_spell: SpellDef) -> Infusion:
	return Infusion.new()


func affinity_of(_spell: SpellDef) -> Dictionary[StringName, int]:
	return {}


func riders(_spell: SpellDef) -> Array[OnHitEffect]:
	return []
