extends GutTest

const _MELEE := preload("res://ui/hud/combat_readout/combat_card_melee.tscn")
const _RANGED := preload("res://ui/hud/combat_readout/combat_card_ranged.tscn")
const _MAGIC := preload("res://ui/hud/combat_readout/combat_card_magic.tscn")
const _DEFENSE := preload("res://ui/hud/combat_readout/combat_card_defense.tscn")

const _RED := Color(0.9451, 0.2689, 0.2453, 1)
const _GREEN := Color(0.3187, 0.7773, 0.4484, 1)
const _BLUE := Color(0.291, 0.5892, 1.0, 1)
const _STEEL := Color(0.8586, 0.9018, 0.9482, 1)


func test_melee_mode_color_is_red() -> void:
	var card := _MELEE.instantiate()
	add_child_autofree(card)
	assert_eq(card.mode_color, _RED)


func test_ranged_mode_color_is_green() -> void:
	var card := _RANGED.instantiate()
	add_child_autofree(card)
	assert_eq(card.mode_color, _GREEN)


func test_magic_mode_color_is_blue() -> void:
	var card := _MAGIC.instantiate()
	add_child_autofree(card)
	assert_eq(card.mode_color, _BLUE)


func test_defense_mode_color_is_steel() -> void:
	var card := _DEFENSE.instantiate()
	add_child_autofree(card)
	assert_eq(card.mode_color, _STEEL)
