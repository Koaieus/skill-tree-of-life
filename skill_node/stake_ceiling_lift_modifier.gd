@tool
extends StatModifier

## The +1 ADD_BASE on `stake_ceiling` a procgen stake raise past the ceiling
## grants. Authored as `stake_ceiling_lift_modifier.tres` and duplicated per
## raise (add_local_modifier dedupes by instance). UNSCALED: a ceiling lift is
## +1 at any allocation level, never laddered by the fill (#376).


func _local_scale_override(_old_al: int, _new_al: int) -> Variant:
	return StatModifier.UNSCALED
