extends StatModifier

## The node-local `healing_received` MULTIPLY [WitherStatus] plants. Authored
## as `wither_modifier.tres` (stat, operation) and duplicated per application,
## the status setting only `value`. UNSCALED so the loss is not laddered by
## allocation depth (#376).


func _local_scale_override(_old_al: int, _new_al: int) -> Variant:
	return StatModifier.UNSCALED
