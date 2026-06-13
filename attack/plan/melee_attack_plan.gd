class_name MeleeAttackPlan
extends AttackPlan                   


var source: SkillNode				# 1 self-allocated pivot                                                                                                                                                                                                                                                                 
var blade_nodes: Array[SkillNode]	# N self-allocated, connected to source                                                                                                                                                                                                                                                  
var blade_target: Vector2			# or whatever describes the arc


func validate() -> Array[String]:
	var errors: Array[String] = []
	if not source:
		errors.append(&'No source node selected')
	if blade_nodes.is_empty():
		errors.append(&'No blade nodes selected')
	return errors
