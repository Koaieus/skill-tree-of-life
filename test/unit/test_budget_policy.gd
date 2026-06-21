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
