@abstract 
class_name AttackPlan
extends RefCounted
## Abstract parent class for a plan for an [Entity] preparing an attack.
#
# Contains information of source and target, and mode of attack.

var attacker: Entity
var mode: BattleSystem.AttackMode


## error messages, empty = valid
@abstract func validate() -> Array[String]

## all required slots filled
func is_valid() -> bool:
	return validate().is_empty()


func _to_string() -> String:
	var cls: String = str(get_script().get_global_name()) if get_script() else "AttackPlan"
	var mode_name: String = BattleSystem.AttackMode.keys()[mode]
	var atk: String = attacker.display_name if attacker != null else "?"
	return "<%s %s by %s>" % [cls, mode_name, atk]
