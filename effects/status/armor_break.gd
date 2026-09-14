class_name ArmorBreakStatus
extends StatusDef

## Armor Break (#877, hub #868 D3/D8 shape): each hit chips a tunable
## FRACTION of node-local `armor` away. `power` IS the fraction removed —
## `reapply = ACCUMULATE` in the authored def makes repeated hits additive on
## that fraction (two 20% hits leave 60% armor, never (1-0.2)^2 = 64%), so a
## fully broken node (`power == power_max == 1.0`) reaches exactly ×0 armor.
## Recovery is `decay_per_tick` per turn, same shape as everything else here.
##
## STUB — behaviour hooks land next commit (red test first).

## Own type so a found modifier can be told apart from any other MULTIPLY on
## `armor`, and UNSCALED so a broken node's armor loss is not laddered by
## allocation depth (#376 — same rationale as Blindness's BlindModifier).
class ArmorBreakModifier:
	extends StatModifier

	func _local_scale_override(_old_al: int, _new_al: int) -> Variant:
		return StatModifier.UNSCALED
