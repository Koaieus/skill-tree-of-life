extends GutTest

## #70 — op-aware contribution string for stat-modifier floaters.

func _mod(op: StatModifier.Operation, val: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = &"strength"
	m.operation = op
	m.value = val
	return m


func test_add_base_positive() -> void:
	assert_eq(_mod(StatModifier.Operation.ADD_BASE, 10.0).contribution_text(), "+10")


func test_add_base_negative() -> void:
	assert_eq(_mod(StatModifier.Operation.ADD_BASE, -5.0).contribution_text(), "-5")


func test_add_bonus_is_flat() -> void:
	assert_eq(_mod(StatModifier.Operation.ADD_BONUS, 4.0).contribution_text(), "+4")


func test_increase_is_percent() -> void:
	assert_eq(_mod(StatModifier.Operation.INCREASE, 20.0).contribution_text(), "+20%")


func test_multiply_fractional() -> void:
	assert_eq(_mod(StatModifier.Operation.MULTIPLY, 1.5).contribution_text(), "×1.5")


func test_multiply_whole_trims_decimals() -> void:
	assert_eq(_mod(StatModifier.Operation.MULTIPLY, 2.0).contribution_text(), "×2")


func test_set_override() -> void:
	assert_eq(_mod(StatModifier.Operation.SET, 13.0).contribution_text(), "=13")

# `test_trigger_signal_exists` lived here and asserted only that
# `Events.has_signal("stat_modifier_changed")` — a signal DECLARATION, which
# passes forever whether or not anything ever emits or connects to it, and
# which was off-topic for a file about `contribution_text()`. Deleted rather
# than rewritten: if the emission is worth guarding, it belongs in a test of
# the emitter, with `watch_signals` + `assert_signal_emitted`.
