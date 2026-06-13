class_name RangedAttackPlan 
extends AttackPlan                                                                                                                                                                                                                                                                               


var target: SkillNode  # 1 enemy node              


func get_firing_positions() -> Array[SkillNode]:
	return attacker.navigator.get_leaf_nodes()

func validate() -> Array[String]:
	var errors: Array[String] = []
	if target == null:
		errors.append(&'No target')
	if target.owned_by == attacker:
		errors.append(&'Target node is not owned by an enemy')
	return errors
