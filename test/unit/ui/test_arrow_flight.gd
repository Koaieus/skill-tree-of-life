extends GutTest

## #1517 — the ranged panel's arrow flights are presentation only: the pure
## per-type diff of two plan lists says how many arrows fly card→bar or
## bar→card, capped at `max_flights_per_change`.


func _list(pairs: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in pairs:
		out.append({"type": p[0], "count": p[1]})
	return out


func _of(reqs: Array[Dictionary], type_id: StringName, dir: StringName) -> Array[Dictionary]:
	return reqs.filter(func(r: Dictionary) -> bool: return r.type == type_id and r.dir == dir)


func test_two_to_five_flies_three_to_the_bar() -> void:
	var reqs := ArrowFlightLayer.diff(_list([[&"poison", 2], [&"arrow", 6]]), _list([[&"poison", 5], [&"arrow", 6]]), 8)
	var up := _of(reqs, &"poison", ArrowFlightLayer.TO_BAR)
	assert_eq(up.size(), 3)
	assert_eq(reqs.size(), 3, "an unchanged type flies nothing")
	assert_eq(up.map(func(r: Dictionary) -> int: return r.index), [2, 3, 4], "the new arrows' slots in the new list")
	assert_eq(up[0].total, 11)


func test_five_to_two_flies_three_back_to_the_pile() -> void:
	var reqs := ArrowFlightLayer.diff(_list([[&"arrow", 4], [&"poison", 5]]), _list([[&"arrow", 4], [&"poison", 2]]), 8)
	var down := _of(reqs, &"poison", ArrowFlightLayer.TO_PILE)
	assert_eq(down.size(), 3)
	assert_eq(down.map(func(r: Dictionary) -> int: return r.index), [6, 7, 8], "the leaving arrows' slots in the old list")
	assert_eq(down[0].total, 9)


func test_a_change_of_three_hundred_is_capped() -> void:
	var reqs := ArrowFlightLayer.diff(_list([]), _list([[&"arrow", 300]]), 8)
	assert_eq(reqs.size(), 8)
	reqs = ArrowFlightLayer.diff(_list([[&"arrow", 300]]), _list([]), 8)
	assert_eq(_of(reqs, &"arrow", ArrowFlightLayer.TO_PILE).size(), 8)
