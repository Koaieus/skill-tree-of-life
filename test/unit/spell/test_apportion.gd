extends GutTest

## [method Apportion.largest_remainder]: whole floors first, each leftover unit
## to the largest fractional remainder, ties to the lower index; the result
## always sums to the total (when any weight is positive), and a zero or
## negative weight never receives a unit.


func _sum(xs: Array[int]) -> int:
	var s := 0
	for x in xs:
		s += x
	return s


func test_exact_proportions_split_exactly() -> void:
	assert_eq(Apportion.largest_remainder(6, [1.0, 2.0, 3.0]), [1, 2, 3] as Array[int])


func test_leftover_goes_to_the_largest_remainder() -> void:
	# quotas 10*[0.15, 0.35, 0.5] = 1.5, 3.5, 5.0 -> floors 1,3,5, one unit left;
	# remainders 0.5, 0.5, 0.0 -> tie, the lower index wins.
	assert_eq(Apportion.largest_remainder(10, [0.15, 0.35, 0.5]), [2, 3, 5] as Array[int])
	# quotas 7*[1,2,4]/7 is exact; 5*[1,2,4]/7 = 0.714, 1.429, 2.857 -> floors 0,1,2,
	# two left -> remainders 0.857 (i2), 0.714 (i0) win.
	assert_eq(Apportion.largest_remainder(5, [1.0, 2.0, 4.0]), [1, 1, 3] as Array[int])


func test_ties_go_to_the_earlier_index() -> void:
	assert_eq(Apportion.largest_remainder(1, [1.0, 1.0, 1.0]), [1, 0, 0] as Array[int])
	assert_eq(Apportion.largest_remainder(2, [1.0, 1.0, 1.0]), [1, 1, 0] as Array[int])
	# The owner's diamond: F's 1:2 split of 1 and of 2 stacks.
	assert_eq(Apportion.largest_remainder(1, [1, 2]), [0, 1] as Array[int])
	assert_eq(Apportion.largest_remainder(2, [1, 1]), [1, 1] as Array[int])


func test_conserves_the_total() -> void:
	var weights := [3, 0.5, 7.25, 1, 1, 2.2]
	for total in range(0, 40):
		var got := Apportion.largest_remainder(total, weights)
		assert_eq(got.size(), weights.size())
		assert_eq(_sum(got), total, "total %d" % total)


func test_zero_or_negative_weight_never_gets_a_unit() -> void:
	var got := Apportion.largest_remainder(5, [0.0, 1.0, -3.0, 1.0])
	assert_eq(got[0], 0)
	assert_eq(got[2], 0)
	assert_eq(_sum(got), 5)


func test_degenerate_inputs_give_all_zeros() -> void:
	assert_eq(Apportion.largest_remainder(5, []), [] as Array[int])
	assert_eq(Apportion.largest_remainder(0, [1.0, 2.0]), [0, 0] as Array[int])
	assert_eq(Apportion.largest_remainder(-3, [1.0, 2.0]), [0, 0] as Array[int])
	assert_eq(Apportion.largest_remainder(5, [0.0, -1.0]), [0, 0] as Array[int])
