extends GutTest

## BudgetPolicy: base range × archetype mult × field scale × role bonus.


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func test_base_range_only() -> void:
	var p := BudgetPolicy.new()
	p.base_min = 3
	p.base_max = 3
	# All scalars default to 1.0 → budget = 3.
	assert_eq(p.compute_budget(&"red", Vector2.ZERO, [], _rng()), 3)


func test_archetype_multiplier_applied() -> void:
	var p := BudgetPolicy.new()
	p.base_min = 4
	p.base_max = 4
	p.archetype_multiplier = {&"red": 2.0, &"blue": 0.5}
	assert_eq(p.compute_budget(&"red", Vector2.ZERO, [], _rng()), 8)
	assert_eq(p.compute_budget(&"blue", Vector2.ZERO, [], _rng()), 2)
	# Unknown archetype → 1.0 (default).
	assert_eq(p.compute_budget(&"green", Vector2.ZERO, [], _rng()), 4)


func test_radial_field_scales_by_position() -> void:
	var p := BudgetPolicy.new()
	p.base_min = 2
	p.base_max = 2
	var field := RadialGradientField.new()
	field.center = Vector2.ZERO
	field.inner_radius = 0.0
	field.outer_radius = 100.0
	field.inner_value = 1.0
	field.outer_value = 4.0
	p.budget_field = field
	# Center → 1.0 × 2 = 2.
	assert_eq(p.compute_budget(&"red", Vector2.ZERO, [], _rng()), 2)
	# Outer rim → 4.0 × 2 = 8.
	assert_eq(p.compute_budget(&"red", Vector2(100, 0), [], _rng()), 8)


func test_role_bonus_multiplies() -> void:
	var p := BudgetPolicy.new()
	p.base_min = 4
	p.base_max = 4
	p.role_bonus = {&"anomalous": 1.75}
	assert_eq(p.compute_budget(&"red", Vector2.ZERO, [&"anomalous"], _rng()), 7)
	assert_eq(p.compute_budget(&"red", Vector2.ZERO, [], _rng()), 4)


func test_floors_at_one() -> void:
	# Aggressively shrink budget → should clamp to 1, not 0.
	var p := BudgetPolicy.new()
	p.base_min = 1
	p.base_max = 1
	p.archetype_multiplier = {&"red": 0.1}
	# 1 × 0.1 → round(0.1) = 0; clamp to 1.
	assert_eq(p.compute_budget(&"red", Vector2.ZERO, [], _rng()), 1)


func test_floor_ceiling_fields_drive_radial_roll() -> void:
	# Two RadialGradientFields: floor lerps 2→8, ceiling lerps 4→16.
	# At the center the roll is uniform in [2, 4]; at the rim in [8, 16].
	# The inner_ring_max < outer_ring_min property is the key benefit
	# (no overlap between bands).
	var p := BudgetPolicy.new()
	p.base_min = -1  # ensure fallbacks are not consulted
	p.base_max = -1
	var floor_field := RadialGradientField.new()
	floor_field.center = Vector2.ZERO
	floor_field.inner_radius = 0.0
	floor_field.outer_radius = 100.0
	floor_field.inner_value = 2.0
	floor_field.outer_value = 8.0
	var ceil_field := RadialGradientField.new()
	ceil_field.center = Vector2.ZERO
	ceil_field.inner_radius = 0.0
	ceil_field.outer_radius = 100.0
	ceil_field.inner_value = 4.0
	ceil_field.outer_value = 16.0
	p.budget_floor_field = floor_field
	p.budget_ceiling_field = ceil_field
	# Drive many rolls and bracket the resulting range per position.
	var rng := _rng(42)
	var center_lo := 1e9
	var center_hi := -1e9
	var rim_lo := 1e9
	var rim_hi := -1e9
	for i in 200:
		var c: float = p.compute_budget(&"red", Vector2.ZERO, [], rng)
		var r: float = p.compute_budget(&"red", Vector2(100, 0), [], rng)
		center_lo = minf(center_lo, c)
		center_hi = maxf(center_hi, c)
		rim_lo = minf(rim_lo, r)
		rim_hi = maxf(rim_hi, r)
	# Center: rolls in [2,4] → after max(1, round) → [2,4]
	assert_true(center_lo >= 2 and center_hi <= 4, "center range was [%s,%s]" % [center_lo, center_hi])
	# Rim: rolls in [8,16]
	assert_true(rim_lo >= 8 and rim_hi <= 16, "rim range was [%s,%s]" % [rim_lo, rim_hi])
	# Bands don't overlap: every center roll ≤ every rim roll.
	assert_true(center_hi <= rim_lo, "bands overlap: center_hi=%s rim_lo=%s" % [center_hi, rim_lo])


func test_swapped_floor_ceiling_is_tolerated() -> void:
	# If author misconfigures floor > ceiling, code swaps internally rather than
	# producing inverted rolls.
	var p := BudgetPolicy.new()
	var hi_field := ConstantField.new()
	hi_field.value = 10.0
	var lo_field := ConstantField.new()
	lo_field.value = 2.0
	p.budget_floor_field = hi_field      # "floor" set high
	p.budget_ceiling_field = lo_field    # "ceiling" set low — wrong, swapped
	for i in 20:
		var b: int = p.compute_budget(&"red", Vector2.ZERO, [], _rng(i))
		assert_true(b >= 2 and b <= 10, "out of range: %d" % b)


func test_composed_factors() -> void:
	var p := BudgetPolicy.new()
	p.base_min = 2
	p.base_max = 2
	p.archetype_multiplier = {&"red": 1.5}
	p.role_bonus = {&"anomalous": 2.0}
	var field := RadialGradientField.new()
	field.center = Vector2.ZERO
	field.inner_radius = 0.0
	field.outer_radius = 100.0
	field.inner_value = 1.0
	field.outer_value = 2.0
	p.budget_field = field
	# 2 × 1.5 × 2.0 (rim) × 2.0 (role) = 12.
	assert_eq(p.compute_budget(&"red", Vector2(100, 0), [&"anomalous"], _rng()), 12)
