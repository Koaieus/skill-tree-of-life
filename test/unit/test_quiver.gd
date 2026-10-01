extends GutTest

## Quiver = the `arrows` PoolStat with per-AmmoType bins (#955, hub #496).
## Built on hand-made objects — capacity is authored on the def and the
## owner tunes it; these tests pin the FORMULA, never the .tres number.

const _DEF := preload("res://stats_system/defs/arrows.tres")


func _quiver(capacity: int) -> Quiver:
	var q := Quiver.new()
	q.definition = _DEF
	q.base_value = float(capacity)
	q.current = 0.0
	return q


func _sum(q: Quiver) -> int:
	var total := 0
	for k in q.ammo_bins():
		total += int(q.ammo_bins()[k])
	return total


func test_add_then_stock_of_reports_the_bin() -> void:
	var q := _quiver(40)
	assert_eq(q.add(&"arrow", 6), 6, "add reports the number actually added")
	assert_eq(q.add(&"poison", 1), 1)
	assert_eq(q.stock_of(&"arrow"), 6)
	assert_eq(q.stock_of(&"poison"), 1)
	assert_eq(q.stock_of(&"fire"), 0, "an unknown type is an empty bin, not an error")
	assert_eq(q.ammo_bins(), {&"arrow": 6, &"poison": 1})


func test_take_never_returns_more_than_the_bin_holds() -> void:
	var q := _quiver(40)
	q.add(&"arrow", 3)
	assert_eq(q.take(&"arrow", 5), 3, "take is clamped by the bin")
	assert_eq(q.stock_of(&"arrow"), 0)
	assert_eq(q.take(&"arrow", 1), 0, "a dry bin yields nothing")
	assert_false(q.ammo_bins().has(&"arrow"), "an empty bin is dropped from the listing")


func test_current_equals_the_base_bin_after_every_transfer() -> void:
	var q := _quiver(10)
	q.add(&"arrow", 4)
	assert_eq(roundi(q.current), q.stock_of(Quiver.BASE_ID))
	q.add(&"poison", 3)
	assert_eq(roundi(q.current), q.stock_of(Quiver.BASE_ID), "a special never moves current")
	q.take(&"arrow", 2)
	assert_eq(roundi(q.current), q.stock_of(Quiver.BASE_ID))
	q.take(&"poison", 1)
	assert_eq(roundi(q.current), q.stock_of(Quiver.BASE_ID))
	q.add(&"arrow", 50)  # overflows the cap
	assert_eq(roundi(q.current), 10)
	assert_eq(q.total_stock(), _sum(q), "total_stock is every bin")
	assert_eq(q.total_stock(), 12)


func test_add_clamps_plain_to_capacity_and_capacity_rise_does_not_gift_arrows() -> void:
	var q := _quiver(10)
	assert_eq(q.add(&"arrow", 25), 10, "only the remaining room is added")
	assert_eq(q.stock_of(&"arrow"), 10)
	assert_eq(q.add(&"arrow", 1), 0, "a full quiver takes no plain arrow")
	q.base_value = 20.0  # a capacity raise through the cap-change policy
	assert_eq(int(q.get_value()), 20)
	assert_eq(roundi(q.current), 10, "PIN: the cap rose, the stock did not")
	assert_eq(q.stock_of(&"arrow"), 10)


func test_a_special_banks_outside_the_plain_capacity() -> void:
	var q := _quiver(10)
	q.add(&"arrow", 10)
	assert_eq(q.add(&"poison", 5), 5, "a full plain quiver still banks every special")
	assert_eq(q.stock_of(&"poison"), 5)
	assert_eq(roundi(q.current), 10, "the special sits beside current")


func test_a_special_clamps_at_its_own_max_stock() -> void:
	var q := _quiver(10)
	var cap := 7
	assert_eq(q.add(&"poison", 5, cap), 5)
	assert_eq(q.add(&"poison", 5, cap), 2, "only the room under the type's cap is added")
	assert_eq(q.stock_of(&"poison"), cap)
	assert_eq(q.add(&"poison", 1, cap), 0, "a special at its cap takes nothing")
	assert_eq(q.room_for(&"poison", cap), 0)
	assert_eq(q.room_for(&"scout", cap), cap)
	assert_eq(q.room_for(Quiver.BASE_ID, cap), 10, "plain room is capacity, never the special cap")


func test_capacity_fall_trims_plain_arrows_only() -> void:
	var q := _quiver(10)
	q.add(&"poison", 4)
	q.add(&"arrow", 6)
	q.base_value = 5.0
	assert_eq(roundi(q.current), 5, "CLAMP: current follows the cap down")
	assert_eq(q.stock_of(&"arrow"), 5, "the plain bin follows current down")
	assert_eq(q.stock_of(&"poison"), 4, "specials never shrink on a capacity change")


func test_base_id_matches_the_roster() -> void:
	assert_eq(Quiver.BASE_ID, AmmoTypeRoster.BASE_ID,
			"Quiver sits below attack/ and keeps its own copy of the base id")


func test_bin_changed_reports_the_type_touched() -> void:
	var q := _quiver(10)
	watch_signals(q)
	q.add(&"arrow", 2)
	assert_signal_emitted_with_parameters(q, "bin_changed", [&"arrow"])
	q.take(&"arrow", 1)
	assert_signal_emit_count(q, "bin_changed", 2)
	q.take(&"fire", 1)
	assert_signal_emit_count(q, "bin_changed", 2, "a no-op take does not emit")


func test_to_dict_round_trips_bins() -> void:
	var q := _quiver(40)
	q.add(&"arrow", 7)
	q.add(&"poison", 2)
	q.add(&"scout", 3)
	var d := q.to_dict()
	var back := _quiver(40)
	back.read_dict(d)
	assert_eq(roundi(back.current), 7, "current is the plain bin")
	assert_eq(back.stock_of(&"scout"), 3)
	assert_eq(back.stock_of(&"arrow"), 7)
	assert_eq(back.stock_of(&"poison"), 2)
	assert_eq(back.ammo_bins(), q.ammo_bins())
	# Through the wire's string keys too (JSON-shaped payloads stringify keys).
	var stringified := d.duplicate(true)
	var bins: Dictionary = {}
	for k in d["bins"]:
		bins[String(k)] = d["bins"][k]
	stringified["bins"] = bins
	var back2 := _quiver(40)
	back2.read_dict(stringified)
	assert_eq(back2.stock_of(&"arrow"), 7)
