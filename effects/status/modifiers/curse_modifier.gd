@tool
extends StatModifier

## The ADD_BASE on `min_damage_taken` a cursed node carries. Authored as `curse_modifier.tres` and duplicated per application, the status
## setting only the runtime-dependent fields. UNSCALED so the effect is not
## laddered by allocation depth (#376).


func _local_scale_override(_old_al: int, _new_al: int) -> Variant:
	return StatModifier.UNSCALED
