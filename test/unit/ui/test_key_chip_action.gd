extends GutTest

## A [KeyChip] can name an InputMap ACTION instead of a hand-typed glyph, so
## the keycap on a button is derived from the binding and cannot drift from
## it when the action is rebound.

const _CHIP := preload("res://ui/common/key_chip.tscn")


func test_keycap_is_derived_from_the_actions_bound_key() -> void:
	assert_eq(KeyChip.keycap_for(&"ui_reload"), "R")
	assert_eq(KeyChip.keycap_for(&"ui_select_manage_mode"), "Tab")


func test_an_unbound_or_unknown_action_yields_no_keycap() -> void:
	assert_eq(KeyChip.keycap_for(&"ui_no_such_action"), "")


func test_setting_action_paints_the_chip_and_shows_it() -> void:
	var chip := _CHIP.instantiate() as KeyChip
	add_child_autofree(chip)
	chip.action = &"ui_reload"
	assert_eq(chip.text, "R")
	assert_true(chip.visible)
	chip.action = &"ui_no_such_action"
	assert_eq(chip.text, "")
	assert_false(chip.visible, "no binding, no chip — an absence, not an empty box")


func test_the_launch_button_advertises_its_own_action() -> void:
	# `ui_launch_attack` is the button's Shortcut; the chip reads the SAME
	# action, so the cap can never disagree with the key that fires it.
	var btn := preload("res://ui/launch_attack_button/launch_attack_button.tscn").instantiate()
	add_child_autofree(btn)
	var chip := btn.find_child("KeyChip", true, false) as KeyChip
	assert_not_null(chip, "the launch button carries a KeyChip")
	if chip == null:
		return
	assert_eq(chip.action, &"ui_launch_attack")
	assert_eq(chip.text, KeyChip.keycap_for(&"ui_launch_attack"))
	assert_true(chip.visible)
