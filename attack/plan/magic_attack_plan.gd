class_name MagicAttackPlan
extends AttackPlan

var source: SkillNode
var spell: Spell

func validate() -> Array[String]:
	var errors: Array[String] = []
	
	if spell:
		errors.append_array(spell.validate(self))
	else:
		errors.append(&'No Spell selected')
	
	return errors

func get_available_spells() -> Array[Spell]:
	return []
