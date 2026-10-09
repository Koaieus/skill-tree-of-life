extends GutTest

## An ammo card wears its type's first status as one [IdentityBadge], so the
## cards read apart at a glance. Everything derives from the [AmmoType]; a
## status-less type shows no badge.

const _CARD_SCENE := preload("res://ui/hud/command_tray/bodies/ammo_card.tscn")
const _ROSTER: AmmoTypeRoster = preload("res://attack/ammo/ammo_type_roster.tres")
const _POISON: AmmoType = preload("res://attack/ammo/types/poison.tres")


func _card(type: AmmoType) -> AmmoCard:
	var card: AmmoCard = _CARD_SCENE.instantiate()
	add_child_autofree(card)
	card.setup(type)
	return card


func _visible_badges(card: AmmoCard) -> Array[IdentityBadge]:
	var out: Array[IdentityBadge] = []
	for n in card.find_children("*", "IdentityBadge", true, false):
		if (n as IdentityBadge).is_visible_in_tree():
			out.append(n)
	return out


func test_a_poison_card_shows_exactly_one_badge_bound_to_poisons_identity() -> void:
	var card := _card(_POISON)
	var badges := _visible_badges(card)
	assert_eq(badges.size(), 1, "exactly one visible identity badge")
	if badges.is_empty():
		return
	assert_not_null(badges[0].identity, "the badge is bound")
	if badges[0].identity == null:
		return
	assert_eq(badges[0].identity.id, _POISON.first_status_def().identity.id, "bound to the status identity")
	assert_eq(badges[0].size_px, card.badge_px, "sized by the card's knob")


func test_the_base_arrow_card_shows_no_badge() -> void:
	var card := _card(_ROSTER.base_type())
	assert_eq(_visible_badges(card).size(), 0, "a status-less type shows no badge")


func test_the_letter_fallback_is_gone() -> void:
	var card := _card(_POISON)
	assert_null(card.find_child("StatusLetter", true, false), "no StatusLetter node remains")


# --- #1515: the tall card's grammar ----------------------------------------

func _click(card: AmmoCard, button: MouseButton) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	(card.get_node("%CountLabel") as Control).gui_input.emit(ev)


func test_count_label_left_click_asks_for_all_right_click_for_none() -> void:
	var card := _card(_POISON)
	watch_signals(card)
	_click(card, MOUSE_BUTTON_LEFT)
	assert_signal_emitted_with_parameters(card, "all_requested", [_POISON.id])
	_click(card, MOUSE_BUTTON_RIGHT)
	assert_signal_emitted_with_parameters(card, "none_requested", [_POISON.id])


func test_the_send_bar_asks_for_its_type_count_and_is_fed_the_numbers() -> void:
	var card := _card(_POISON)
	card.set_stock(7, 2)
	card.set_count(3, 7)
	var bar := card.get_node("%SendBar") as SendBar
	var pile := card.get_node("%SheafPile") as SheafPile
	assert_eq([bar.stock, bar.value, pile.count], [7, 3, 7], "fed stock / count / pile")
	watch_signals(card)
	bar.value_requested.emit(5)
	assert_signal_emitted_with_parameters(card, "set_requested", [_POISON.id, 5])


func test_only_the_fill_card_shows_the_toggle_and_it_reports() -> void:
	var special := _card(_POISON)
	assert_false((special.get_node("%FillToggle") as Control).visible, "no toggle on a special")
	var base := _card(_ROSTER.base_type())
	base.has_fill_toggle = true
	var toggle := base.get_node("%FillToggle") as Button
	assert_true(toggle.visible)
	watch_signals(base)
	toggle.button_pressed = false
	assert_signal_emitted_with_parameters(base, "fill_toggled", [false])


func test_the_card_is_taller_than_wide_and_the_effect_is_the_tooltip() -> void:
	var card := _card(_POISON)
	assert_gt(card.custom_minimum_size.y, card.custom_minimum_size.x, "tall card")
	assert_string_contains(card.tooltip_text, AmmoCard.effect_line(_POISON))
