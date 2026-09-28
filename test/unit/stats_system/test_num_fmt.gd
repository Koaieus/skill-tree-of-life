extends GutTest

## NumFmt.num — the one display rule for a game number: it never rounds a
## value (values are floored once at their source), it only snaps float noise
## to the whole number it already is, and otherwise prints two trimmed decimals.


func test_whole_value_prints_bare() -> void:
	assert_eq(NumFmt.num(3.0), "3")


func test_float_noise_below_a_whole_snaps_up_not_truncates() -> void:
	assert_eq(NumFmt.num(2.9999999), "3")


func test_negative_float_noise_snaps_to_its_whole() -> void:
	assert_eq(NumFmt.num(-2.9999999), "-3")


func test_one_decimal_is_trimmed() -> void:
	assert_eq(NumFmt.num(1.5), "1.5")


func test_two_decimals_are_kept() -> void:
	assert_eq(NumFmt.num(1.25), "1.25")


func test_float_sum_noise_prints_clean() -> void:
	assert_eq(NumFmt.num(0.1 + 0.2), "0.3")


func test_stat_def_int_branch_prints_whole() -> void:
	assert_eq(StatDef.format_number(StatDef.ValueType.INT, 7.0), "7")


func test_stat_def_bool_branch_unchanged() -> void:
	assert_eq(StatDef.format_number(StatDef.ValueType.BOOL, 1.0), "True")
	assert_eq(StatDef.format_number(StatDef.ValueType.BOOL, 0.0), "False")


func test_stat_def_float_branch_delegates() -> void:
	assert_eq(StatDef.format_number(StatDef.ValueType.FLOAT, 2.9999999), "3")
	assert_eq(StatDef.format_number(StatDef.ValueType.FLOAT, 1.25), "1.25")
