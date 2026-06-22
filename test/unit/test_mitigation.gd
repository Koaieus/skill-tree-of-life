extends GutTest

## Mitigation.apply — damage formula `max(min_damage_taken, raw - armor)`,
## TRUE bypass, zero-raw passthrough.

const _BOARD := preload("res://entity/default_entity_board.tres")


func _board() -> StatBoard:
	return _BOARD.duplicate(true) as StatBoard


func _raw(amount: float, type: int = DamageInstance.Type.PHYSICAL) -> DamageInstance:
	var d := DamageInstance.new()
	d.amount = amount
	d.type = type
	return d


func test_no_armor_no_floor_passes_through() -> void:
	var b := _board()
	b.armor.base_value = 0.0
	b.min_damage_taken.base_value = 0.0
	assert_almost_eq(Mitigation.apply(_raw(7.0), b), 7.0, 0.001)


func test_armor_reduces_flat() -> void:
	var b := _board()
	b.armor.base_value = 3.0
	b.min_damage_taken.base_value = 0.0
	assert_almost_eq(Mitigation.apply(_raw(10.0), b), 7.0, 0.001)


func test_floor_applies_when_armor_exceeds_raw() -> void:
	var b := _board()
	b.armor.base_value = 20.0
	b.min_damage_taken.base_value = 3.0
	assert_almost_eq(Mitigation.apply(_raw(5.0), b), 3.0, 0.001)


func test_zero_raw_stays_zero_even_with_floor() -> void:
	var b := _board()
	b.armor.base_value = 0.0
	b.min_damage_taken.base_value = 3.0
	assert_almost_eq(Mitigation.apply(_raw(0.0), b), 0.0, 0.001)


func test_true_damage_bypasses_armor_and_floor() -> void:
	var b := _board()
	b.armor.base_value = 99.0
	b.min_damage_taken.base_value = 99.0
	assert_almost_eq(Mitigation.apply(_raw(7.0, DamageInstance.Type.TRUE), b), 7.0, 0.001)


func test_negative_floor_allows_healing_via_overkill_armor() -> void:
	var b := _board()
	b.armor.base_value = 10.0
	b.min_damage_taken.base_value = -5.0
	# raw - armor = 3 - 10 = -7; max(-5, -7) = -5 → "damage" is negative (heal).
	assert_almost_eq(Mitigation.apply(_raw(3.0), b), -5.0, 0.001)
