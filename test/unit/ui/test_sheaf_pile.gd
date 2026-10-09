extends GutTest

## [method SheafPile.marks] decomposes a count into sheaf tiers: the marks never
## claim more than the count, and `+` appears exactly when the count outgrows
## what [code]max_marks[/code] of the largest tier can show. Swept, never pinned
## to the default tiers.

const _CONFIGS := [
	[[1, 5, 25], 5],
	[[1, 5, 25], 3],
	[[1, 4, 16, 64], 6],
	[[1, 10], 4],
	[[1], 7],
]


func _value(m: Array[int], tiers: PackedInt32Array) -> int:
	var total := 0
	for t in m:
		if t != SheafPile.PLUS:
			total += tiers[t]
	return total


func test_marks_never_claim_more_than_the_count() -> void:
	for cfg in _CONFIGS:
		var tiers := PackedInt32Array(cfg[0])
		var max_marks: int = cfg[1]
		var bad := 0
		for count in range(0, 1000):
			var m := SheafPile.marks(count, tiers, max_marks)
			if _value(m, tiers) > count:
				bad += 1
		assert_eq(bad, 0, "summed value <= count for tiers %s, max %d" % [tiers, max_marks])


func test_plus_appears_exactly_past_capacity() -> void:
	for cfg in _CONFIGS:
		var tiers := PackedInt32Array(cfg[0])
		var max_marks: int = cfg[1]
		var capacity: int = max_marks * tiers[tiers.size() - 1]
		var wrong := []
		for count in range(0, 1000):
			var m := SheafPile.marks(count, tiers, max_marks)
			var has_plus := m.has(SheafPile.PLUS)
			if has_plus != (count > capacity):
				wrong.append(count)
		assert_eq(wrong.size(), 0, "plus iff count > %d for tiers %s: wrong at %s" % [capacity, tiers, wrong.slice(0, 5)])


func test_marks_never_exceed_max_marks_and_show_something_when_stocked() -> void:
	for cfg in _CONFIGS:
		var tiers := PackedInt32Array(cfg[0])
		var max_marks: int = cfg[1]
		for count in range(0, 1000):
			var m := SheafPile.marks(count, tiers, max_marks)
			var drawn := m.filter(func(t: int) -> bool: return t != SheafPile.PLUS).size()
			if drawn > max_marks or (count > 0) != (drawn > 0):
				fail_test("count %d tiers %s max %d -> %s" % [count, tiers, max_marks, m])
				return
	pass_test("all counts within max_marks")


func test_below_capacity_the_marks_are_exact_when_they_fit() -> void:
	# A count whose greedy decomposition fits the mark budget is shown exactly.
	var tiers := PackedInt32Array([1, 5, 25])
	var max_marks := 5
	var count: int = tiers[2] + tiers[1] + tiers[0]
	assert_eq(_value(SheafPile.marks(count, tiers, max_marks), tiers), count)
