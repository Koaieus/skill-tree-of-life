extends GutTest

## SurplusPoolStat: a transient budget bin sitting OUTSIDE the cap (#156).
##   available() == roundi(current) + surplus   (may exceed .value)
## Surplus is inert to restore_to_full() and the modifier pipeline (incl. SET),
## overwritten (not accumulated) by set_surplus(), and spent surplus-first.

const _DEF := preload("res://stats_system/defs/deallocation_points.tres")


## Pool at `current/current` — base_value matches so the cap equals current.
func _fresh(current: int = 3) -> SurplusPoolStat:
	var sp := SurplusPoolStat.new()
	sp.definition = _DEF
	sp.base_value = float(current)
	sp.current = float(current)
	return sp


func _cap(sp: SurplusPoolStat) -> int:
	return int(sp.value)


func _set_mod(id: StringName, v: float) -> StatModifier:
	var mod := StatModifier.new()
	mod.stat_id = id
	mod.operation = StatModifier.Operation.SET
	mod.value = v
	return mod


func _add_base_mod(id: StringName, v: float) -> StatModifier:
	var mod := StatModifier.new()
	mod.stat_id = id
	mod.operation = StatModifier.Operation.ADD_BASE
	mod.value = v
	return mod


# --- initial state ----------------------------------------------------------

func test_fresh_has_zero_surplus() -> void:
	var sp := _fresh(3)
	assert_eq(sp.surplus, 0)
	assert_eq(sp.available(), 3)
	assert_eq(_cap(sp), 3)


# --- surplus is inert to turn-start REFILL ----------------------------------

func test_surplus_survives_restore_to_full() -> void:
	var sp := _fresh(3)
	sp.set_surplus(4)
	sp.deplete(2)  # spend from surplus → current untouched, surplus 2
	sp.restore_to_full()
	assert_eq(sp.current, 3.0, "current refilled to cap")
	assert_eq(sp.surplus, 2, "surplus untouched by restore_to_full")
	assert_eq(sp.available(), 5)


# --- surplus is inert to cap modifiers --------------------------------------

func test_surplus_inert_to_cap_modifier_up() -> void:
	var sp := _fresh(3)
	sp.set_surplus(2)
	sp.add_modifier(_add_base_mod(&"deallocation_points", 5.0))
	assert_eq(_cap(sp), 8, "cap rose")
	assert_eq(sp.surplus, 2, "surplus unchanged by cap rise")


func test_surplus_inert_to_cap_modifier_down() -> void:
	var sp := _fresh(3)
	sp.set_surplus(2)
	sp.add_modifier(_add_base_mod(&"deallocation_points", -2.0))
	assert_eq(_cap(sp), 1, "cap fell — current clamps to it")
	assert_eq(sp.current, 1.0, "current clamped to lowered cap")
	assert_eq(sp.surplus, 2, "surplus NOT clamped by the cap")
	assert_eq(sp.available(), 3)


# --- the pacifist case: surplus survives a SET on the cap -------------------

func test_surplus_survives_set_cap_zero() -> void:
	var sp := _fresh(3)
	sp.add_modifier(_set_mod(&"deallocation_points", 0.0))
	sp.set_surplus(4)
	assert_eq(_cap(sp), 0, "SET short-circuits the cap to 0")
	assert_eq(sp.current, 0.0, "current clamped to the zero cap")
	assert_eq(sp.available(), 4, "entire budget lives in surplus")
	# Four deplete(1) succeed against surplus; the fifth floors at 0.
	for i in 4:
		sp.deplete(1)
	assert_eq(sp.available(), 0, "surplus fully drained")
	sp.deplete(1)
	assert_eq(sp.available(), 0, "fifth deplete cannot go below zero")


# --- set_surplus overwrites, never accumulates ------------------------------

func test_set_surplus_overwrites() -> void:
	var sp := _fresh(3)
	sp.set_surplus(4)
	sp.set_surplus(1)
	assert_eq(sp.surplus, 1, "second set_surplus overwrites, not adds")


func test_set_surplus_clamps_negative_to_zero() -> void:
	var sp := _fresh(3)
	sp.set_surplus(2)
	sp.set_surplus(-5)
	assert_eq(sp.surplus, 0)


# --- deplete drains surplus before current ----------------------------------

func test_deplete_drains_surplus_first() -> void:
	var sp := _fresh(3)
	sp.set_surplus(2)
	sp.deplete(3)  # 2 from surplus, 1 from current
	assert_eq(sp.surplus, 0)
	assert_eq(sp.current, 2.0)
	assert_eq(sp.available(), 2)


func test_deplete_within_surplus_leaves_current() -> void:
	var sp := _fresh(3)
	sp.set_surplus(2)
	sp.deplete(1)
	assert_eq(sp.surplus, 1)
	assert_eq(sp.current, 3.0, "current untouched while surplus covers the cost")


# --- available() may exceed the cap -----------------------------------------

func test_available_exceeds_cap_with_surplus() -> void:
	var sp := _fresh(3)
	sp.set_surplus(4)
	assert_eq(sp.available(), 7)
	assert_gt(sp.available(), _cap(sp))


# --- negative / zero deplete is set_current-equivalent (no surplus touched) --

func test_deplete_zero_is_noop_on_surplus() -> void:
	var sp := _fresh(3)
	sp.set_surplus(2)
	sp.deplete(0)
	assert_eq(sp.surplus, 2)
	assert_eq(sp.current, 3.0)


func test_negative_deplete_replenishes_current_not_surplus() -> void:
	var sp := _fresh(1)  # cap 1, current 1
	sp.base_value = 3.0  # cap now 3, current still 1
	sp.set_surplus(2)
	sp.deplete(-1)  # equivalent to set_current(current + 1)
	assert_eq(sp.current, 2.0, "negative deplete raises current via base path")
	assert_eq(sp.surplus, 2, "surplus untouched by a negative deplete")
