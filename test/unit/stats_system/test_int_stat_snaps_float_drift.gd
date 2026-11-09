extends GutTest

## An INT stat floors its finished total once (ADR 0016). The bins accumulate
## by delta, so a total that is a whole number on paper can sit one ULP under
## it; the floor must not turn that noise into a missing point. A total that
## is genuinely short of the next whole number still floors down.

var _board: EntityStatBoard = null


func before_each() -> void:
	_board = EntityStatBoard.new()
	var s := ScalarStat.new()
	s.definition = StatRegistry.get_def(&"blade_damage")
	s.base_value = 0.0
	_board.set(&"blade_damage", s)


func _add(value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = &"blade_damage"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = value
	_board.add_modifier(m)


func test_ten_tenths_read_as_one() -> void:
	for i in 10:
		_add(0.1)
	assert_eq(int(_board.get_value(&"blade_damage")), 1, "0.1 × 10 is one point, not zero")


func test_a_total_short_of_the_threshold_still_floors_down() -> void:
	for i in 9:
		_add(0.1)
	_add(0.09)
	assert_eq(int(_board.get_value(&"blade_damage")), 0, "0.99 has not reached the point")


func test_a_negative_whole_total_keeps_its_value() -> void:
	for i in 10:
		_add(-0.1)
	assert_eq(int(_board.get_value(&"blade_damage")), -1, "-0.1 × 10 is minus one")
