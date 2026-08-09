extends GutTest

## #289 — AttributeRules reports the board's ACTUAL intrinsics. The hardcoded
## `match` it replaced had drifted: it claimed "+1 / 10 STR" for blade size
## while the formula divided by 20, and "decade of WIS" for XP regen while the
## formula divided by 2. These tests read the shipped board, so a future
## divisor change either updates the text or fails here.

const BOARD := preload("res://entity/default_entity_board.tres")

var _board: EntityStatBoard = null


func before_each() -> void:
	_board = BOARD.duplicate(true)
	_board.apply_intrinsics()


func _lines(attr: StringName) -> Array[String]:
	return AttributeRules.describe(attr, _board)


func test_null_board_is_empty() -> void:
	assert_eq(AttributeRules.describe(&"strength", null).size(), 0)


func test_unknown_attribute_is_empty() -> void:
	assert_eq(_lines(&"not_a_stat").size(), 0)


func test_strength_lists_both_blade_rules_with_the_real_divisors() -> void:
	var lines := _lines(&"strength")
	assert_eq(lines.size(), 2, "blade damage + blade size")
	assert_string_contains(lines[0], "per 10 STR")
	assert_string_contains(lines[1], "per 20 STR")


func test_wisdom_reports_the_current_xp_rule_not_the_retired_decade_one() -> void:
	var lines := _lines(&"wisdom")
	assert_eq(lines.size(), 1)
	assert_string_contains(lines[0], "per 2 WIS")
	assert_false(lines[0].contains("decade"), "the decade rule is long gone")


func test_perception_line_carries_the_live_value() -> void:
	_board.perception.base_value = 30.0
	var lines := _lines(&"perception")
	assert_eq(lines.size(), 1)
	assert_string_contains(lines[0], "per PER")
	assert_string_contains(lines[0], "-> %s" % str(_board.vision_range.value))


func test_constitution_is_no_longer_blank() -> void:
	# The old `match` had no CON case at all (flagged in .claude/rules/stats-system.md).
	assert_gt(_lines(&"constitution").size(), 0, "CON drives node_health and health")


func test_intelligence_covers_mana_and_its_regen() -> void:
	var lines := _lines(&"intelligence")
	assert_gte(lines.size(), 2)
	var joined := "\n".join(lines)
	assert_string_contains(joined, "per 10 INT")
	assert_string_contains(joined, "per ×10 INT")


func test_no_hardcoded_rule_strings_remain_in_the_source() -> void:
	# The docstring still QUOTES the old literals as the cautionary tale, so
	# this looks for the shapes that only a live lookup table would carry.
	var src := FileAccess.get_file_as_string("res://ui/hud/attribute_rules.gd")
	assert_false(src.contains("match attr_id"), "no per-attribute rule table")
	assert_false(src.contains("+1 hop / 10 DEX"), "no transcribed rule literals")
	assert_false(src.contains("+2% / PER"), "no transcribed rule literals")
