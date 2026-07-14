extends GutTest

## CompositeField: folds children via SUM / MAX / MUL.


func _const(v: float) -> ConstantField:
	var f := ConstantField.new()
	f.value = v
	return f


func test_empty_children_is_neutral() -> void:
	var f := CompositeField.new()
	assert_almost_eq(f.sample(Vector2.ZERO), 1.0, 0.0001)


func test_sum_mode() -> void:
	var f := CompositeField.new()
	f.mode = CompositeField.Mode.SUM
	f.children = [_const(2.0), _const(3.0)]
	assert_almost_eq(f.sample(Vector2.ZERO), 5.0, 0.0001)


func test_mul_mode() -> void:
	var f := CompositeField.new()
	f.mode = CompositeField.Mode.MUL
	f.children = [_const(2.0), _const(3.0)]
	assert_almost_eq(f.sample(Vector2.ZERO), 6.0, 0.0001)


func test_max_mode() -> void:
	var f := CompositeField.new()
	f.mode = CompositeField.Mode.MAX
	f.children = [_const(2.0), _const(5.0), _const(1.0)]
	assert_almost_eq(f.sample(Vector2.ZERO), 5.0, 0.0001)


func test_nested_composite() -> void:
	var inner := CompositeField.new()
	inner.mode = CompositeField.Mode.SUM
	inner.children = [_const(1.0), _const(1.0)]
	var outer := CompositeField.new()
	outer.mode = CompositeField.Mode.MUL
	outer.children = [inner, _const(3.0)]
	# inner = 2.0, outer = 2.0 * 3.0 = 6.0
	assert_almost_eq(outer.sample(Vector2.ZERO), 6.0, 0.0001)


func test_null_children_are_skipped() -> void:
	var f := CompositeField.new()
	f.mode = CompositeField.Mode.SUM
	f.children = [_const(2.0), null]
	assert_almost_eq(f.sample(Vector2.ZERO), 2.0, 0.0001)
