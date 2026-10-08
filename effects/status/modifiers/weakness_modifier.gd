@tool
extends StatModifier

## The MULTIPLY a weakened node carries per stat (`stat_id` set per stat). Authored as `weakness_modifier.tres` and duplicated per application, the status
## setting only the runtime-dependent fields. UNSCALED so the effect is not
## laddered by allocation depth (#376).


func _local_scale_override(_old_al: int, _new_al: int) -> Variant:
	return StatModifier.UNSCALED
