extends GutTest
## CardFan geometry and signals: slots depend only on their index, read off the
## fan's own knobs, never pixels and never the knob defaults.

const _FAN := preload("res://ui/card_fan/card_fan.tscn")

var _catalog: TempUpgradeCatalog = preload("res://attack/melee/temp_upgrade_catalog.tres")
var _fan: CardFan


func before_each() -> void:
	_fan = _FAN.instantiate() as CardFan
	add_child_autofree(_fan)


func _slot(i: int) -> Vector2:
	return CardFan.slot_position(i, _fan.ring_radius_px, _fan.slot_step_deg,
			_fan.max_arc_deg, _fan.ring_gap_px)


func _entries(n: int) -> Array[PackedScene]:
	var offered := _catalog.offered()
	assert_gte(offered.size(), n, "the catalog offers at least %d kinds" % n)
	var out: Array[PackedScene] = []
	for i in n:
		out.append(offered[i])
	return out


func _costs(scene: PackedScene) -> Dictionary[StringName, int]:
	return SkillNodeAddon.temp_costs_of(scene)


## The slot a card sits in, as an offset from the hub's centre.
func _card_slot(card: Control) -> Vector2:
	return card.position + card.size * 0.5 - _fan.get_node("%Cards").position


func test_slot_position_ignores_the_entry_count() -> void:
	var first := _slot(2)
	_fan.bind(_entries(3), _costs, [])
	var of_three := _card_slot(_fan.cards()[2])
	_fan.bind(_entries(5), _costs, [])
	var of_five := _card_slot(_fan.cards()[2])
	assert_ne(first, Vector2.ZERO, "slot 2 sits off the hub")
	assert_almost_eq(of_three, first, Vector2.ONE * 0.01, "slot 2 of 3 is the static slot")
	assert_almost_eq(of_five, first, Vector2.ONE * 0.01, "slot 2 of 5 is slot 2 of 3")


func test_first_slot_is_twelve_o_clock_and_slots_run_clockwise() -> void:
	var s0 := _slot(0)
	assert_almost_eq(s0, Vector2(0.0, -_fan.ring_radius_px), Vector2.ONE * 0.01, "slot 0 straight up")
	assert_gt(_slot(1).x, 0.0, "slot 1 is clockwise of 12 o'clock")
	assert_almost_eq(_slot(1).length(), _fan.ring_radius_px, 0.01, "same ring")


func test_slots_past_the_max_arc_land_on_a_farther_ring() -> void:
	var per_ring := floori(_fan.max_arc_deg / _fan.slot_step_deg) + 1
	for i in per_ring:
		assert_almost_eq(_slot(i).length(), _fan.ring_radius_px, 0.01, "slot %d is on the first ring" % i)
	var outer := _slot(per_ring)
	assert_gt(outer.length(), _fan.ring_radius_px + 0.01, "slot %d starts the next ring" % per_ring)
	assert_gt(_slot(2 * per_ring).length(), outer.length() + 0.01, "a third ring is farther again")


func test_binding_three_entries_instances_three_same_size_cards() -> void:
	_fan.bind(_entries(3), _costs, [])
	var cards := _fan.cards()
	assert_eq(cards.size(), 3, "one card per entry")
	assert_eq(_fan.get_node("%Cards").get_child_count(), 3, "and nothing else in the card layer")
	var size0 := cards[0].get_combined_minimum_size()
	assert_gt(size0.x, 0.0, "a card has a width")
	for c in cards:
		assert_eq(c.get_combined_minimum_size(), size0, "every card is the same size")
	_fan.bind(_entries(2), _costs, [])
	assert_eq(_fan.cards().size(), 2, "a rebind replaces the cards")
	assert_eq(_fan.get_node("%Cards").get_child_count(), 2, "with no stragglers")


func test_a_lit_entry_reads_armed() -> void:
	var entries := _entries(2)
	_fan.bind(entries, _costs, [entries[1]])
	assert_eq(_fan.cards()[0].state, TempUpgradeButton.State.AVAILABLE)
	assert_eq(_fan.cards()[1].state, TempUpgradeButton.State.ARMED)


func test_clicking_a_card_emits_picked_with_its_scene() -> void:
	var entries := _entries(3)
	_fan.bind(entries, _costs, [])
	watch_signals(_fan)
	_fan.cards()[1].pressed.emit()
	assert_signal_emitted_with_parameters(_fan, "picked", [entries[1]])


func test_the_hub_emits_hub_pressed() -> void:
	_fan.bind(_entries(1), _costs, [])
	watch_signals(_fan)
	(_fan.get_node("%Hub") as Button).pressed.emit()
	assert_signal_emitted(_fan, "hub_pressed")
	assert_signal_not_emitted(_fan, "picked")


func test_a_right_click_on_a_card_dismisses_the_fan() -> void:
	_fan.bind(_entries(1), _costs, [])
	watch_signals(_fan)
	# The card's inner Button covers it and takes the click, so the event lands
	# there, not on the card control.
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	(_fan.cards()[0].get_node("%Button") as Control).gui_input.emit(ev)
	assert_signal_emitted(_fan, "dismissed")
	assert_signal_not_emitted(_fan, "picked")
