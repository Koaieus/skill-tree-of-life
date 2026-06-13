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
