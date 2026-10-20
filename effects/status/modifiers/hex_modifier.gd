@tool
extends StatModifier

## The node-local `status_resistance` ADD_BONUS [HexStatus] plants. Authored
## as `hex_modifier.tres` (stat, operation) and duplicated per application,
## the status setting only `value`. `status_resistance` is the family parent
## of every `<aspect>_resistance` (ADR 0029), so one modifier reaches them
## all. UNSCALED so the shred is not laddered by allocation depth (#376).


func _local_scale_override(_old_al: int, _new_al: int) -> Variant:
	return StatModifier.UNSCALED
