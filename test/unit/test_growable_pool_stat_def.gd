extends GutTest

## GrowablePoolStatDef growth math + post-grow modes.
##
## Pool semantics: when `current` crosses up to the cap, the def grows the cap
## by `old_max * growth_factor + growth_flat`, then post_grow_mode decides
## what happens to current:
##   - KEEP: current parks at the old cap; new headroom = delta.
##   - RESET: current drops to min_value.
##   - OVERFLOW: the level-up consumed `old_max` worth of replenish; the new
##     level starts at just the leftover (`excess`).


func _def(flat: float, factor: float, mode: int) -> GrowablePoolStatDef:
	var d := GrowablePoolStatDef.new()
	d.id = &"test_xp"
	d.growth_flat = flat
	d.growth_factor = factor
	d.post_grow_mode = mode
	return d


func _pool(def: GrowablePoolStatDef, max_v: int, current: int) -> PoolStat:
	var p := PoolStat.new()
	p.definition = def
	p.base_value = float(max_v)
	p.current = float(current)
	return p


# --- OVERFLOW: the bug fix ---------------------------------------------------

## At 8/10 + replenish 5: total earned = 5, level cost = 10, but we already
## had 8 banked, so leftover = 8 + 5 - 10 = 3. New state: 3 / 15.
func test_overflow_carries_only_excess_not_current_plus_excess() -> void:
	var p := _pool(_def(5.0, 1.0, GrowablePoolStatDef.PostGrowMode.OVERFLOW), 10, 8)
	p.replenish(5)
	assert_eq(int(p.value), 15, "new max should be old_max + growth_flat")
	assert_eq(int(p.current), 3, "current should carry only the excess (5 earned - 2 needed to fill old cap)")


## Edge case: nearly full + small replenish. Old code awarded `old_max` of
## unearned XP — at 9/10 + 1, it landed at 10/15 instead of 0/15.
func test_overflow_full_replenish_lands_at_zero() -> void:
	var p := _pool(_def(5.0, 1.0, GrowablePoolStatDef.PostGrowMode.OVERFLOW), 10, 9)
	p.replenish(1)
	assert_eq(int(p.value), 15)
	assert_eq(int(p.current), 0, "exactly filling the cap should leave 0 excess in the new level")


## Cascade: 0/10 + replenish 30 (flat=5). Fills cap (excess 20), level → 15.
## set_current(excess=20) on new cap=15 → fills again (excess 5), level → 20.
## set_current(5) on cap=20 → parks at 5. Result: 5 / 20.
func test_overflow_huge_replenish_cascades_through_levels() -> void:
	var p := _pool(_def(5.0, 1.0, GrowablePoolStatDef.PostGrowMode.OVERFLOW), 10, 0)
	p.replenish(30)
	assert_eq(int(p.value), 20, "two level-ups: 10 → 15 → 20")
	assert_eq(int(p.current), 5, "5 XP left over after the second level-up consumed 15")


# --- RESET ------------------------------------------------------------------

func test_reset_drops_current_to_min() -> void:
	var p := _pool(_def(5.0, 1.0, GrowablePoolStatDef.PostGrowMode.RESET), 10, 9)
	p.replenish(5)
	assert_eq(int(p.value), 15)
	assert_eq(int(p.current), 0, "RESET drops current to min_value regardless of excess")


# --- KEEP -------------------------------------------------------------------

func test_keep_parks_current_at_old_cap() -> void:
	var p := _pool(_def(5.0, 1.0, GrowablePoolStatDef.PostGrowMode.KEEP), 10, 8)
	p.replenish(5)
	assert_eq(int(p.value), 15)
	assert_eq(int(p.current), 10, "KEEP parks current at the old cap; new headroom = delta")


# --- growth math ------------------------------------------------------------

func test_growth_flat_only_is_linear() -> void:
	var d := _def(5.0, 1.0, GrowablePoolStatDef.PostGrowMode.RESET)
	var p := _pool(d, 10, 9)
	p.replenish(1)
	assert_eq(int(p.value), 15, "first level: +5")
	p.set_current(float(p.value) - 1.0)
	p.replenish(1)
	assert_eq(int(p.value), 20, "second level: +5 again, flat curve")


func test_growth_factor_compounds() -> void:
	var d := _def(0.0, 2.0, GrowablePoolStatDef.PostGrowMode.RESET)
	var p := _pool(d, 10, 9)
	p.replenish(1)
	assert_eq(int(p.value), 20, "factor 2.0 doubles the cap on level-up")


func test_misconfigured_growth_is_noop() -> void:
	# factor < 1 with no flat → new_max < old_max → delta <= 0 → bail.
	var d := _def(0.0, 0.5, GrowablePoolStatDef.PostGrowMode.RESET)
	var p := _pool(d, 10, 9)
	p.replenish(1)
	assert_eq(int(p.value), 10, "misconfigured growth should not shrink the cap")
	assert_eq(int(p.current), 10, "no level-up means current stays at cap")
