@tool
class_name GrowablePoolStatDef
extends PoolStatDef

## A gauge that grows when filled — XP-style. Replenishing up to the cap
## triggers growth: the cap bumps via `base_value`, and `post_grow_mode`
## decides what happens to `current`.
##
## Growth writes `base_value` directly, bypassing the modifier pipeline —
## so it does NOT trigger StandardPoolStatDef's heal-on-max-increase
## (analogous to SkillPointStat.claim's "mints without healing" pattern).

enum PostGrowMode {
	KEEP,      ## current parks at the old cap; new headroom = delta
	RESET,     ## current drops to min_value; full new cap is empty
	OVERFLOW,  ## current carries the unused replenish into the new level
}

## new_max = coerce(old_max * growth_factor + growth_flat)
## Coercion uses the stat's value_type, so int pools snap and float pools don't.
## Flat alone → linear curve (XP: +5 per level). Factor > 1 → mild exponential.
@export var growth_flat: float = 0.0
@export var growth_factor: float = 1.0

@export var post_grow_mode: PostGrowMode = PostGrowMode.RESET


func on_pool_filled(stat: PoolStat, excess: float) -> void:
	var old_max := float(stat.get_value())
	var new_max_raw := old_max * growth_factor + growth_flat
	var new_max := float(stat._coerce(new_max_raw))
	var delta := new_max - old_max
	if delta <= 0.0:
		return  # misconfigured (factor < 1 + tiny flat) or no-op
	stat.base_value += delta
	match post_grow_mode:
		PostGrowMode.KEEP:
			pass  # current stays at the old cap; new headroom = delta
		PostGrowMode.RESET:
			stat.set_current(float(stat._min_value()))
		PostGrowMode.OVERFLOW:
			# Carries excess forward. May cascade through multiple level-ups
			# if the inbound replenish was huge — that's intentional.
			stat.set_current(stat.current + excess)
