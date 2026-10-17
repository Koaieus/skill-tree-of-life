extends GutTest

## TempQuickbar: the Z–B favourites, pure logic. Fills only open, unpinned slots,
## in the order given; a manual swap pins its slot against every later fill.

var _scenes: Array[PackedScene] = []


func before_all() -> void:
	# Distinct PackedScene identities are all the bar compares; never loaded.
	for i in 8:
		_scenes.append(PackedScene.new())


func _first(n: int) -> Array[PackedScene]:
	return _scenes.slice(0, n)


func test_the_slot_count_is_the_hotkey_count() -> void:
	var bar := TempQuickbar.new()
	assert_eq(bar.slots.size(), PlayerInputController.TEMP_UPGRADE_HOTKEYS.size())
	assert_eq(bar.pinned.size(), bar.slots.size())
	for s in bar.slots:
		assert_null(s, "a fresh bar is empty")


func test_autofill_fills_in_order_and_stops_at_five() -> void:
	var bar := TempQuickbar.new()
	bar.autofill(_first(7))
	assert_eq(bar.slots, _first(5), "first five, in the order given")
	assert_true(bar.autofilled)


func test_autofill_with_fewer_kinds_leaves_the_rest_empty() -> void:
	var bar := TempQuickbar.new()
	bar.autofill(_first(2))
	assert_eq(bar.scene_at(0), _scenes[0])
	assert_eq(bar.scene_at(1), _scenes[1])
	assert_null(bar.scene_at(2))
	assert_null(bar.scene_at(99), "out of range reads empty")


func test_on_aspect_gained_fills_only_open_slots_in_order() -> void:
	var bar := TempQuickbar.new()
	bar.autofill(_first(2))
	bar.on_aspect_gained([_scenes[5], _scenes[0], _scenes[6]] as Array[PackedScene])
	assert_eq(bar.slots, [_scenes[0], _scenes[1], _scenes[5], _scenes[6], null] as Array[PackedScene],
			"filled slots untouched, a kind already on the bar not doubled")


func test_a_pinned_slot_is_never_overwritten() -> void:
	var bar := TempQuickbar.new()
	bar.swap(0, null)
	bar.swap(1, _scenes[7])
	assert_true(bar.pinned[0])
	assert_true(bar.pinned[1])
	bar.autofill(_first(5))
	bar.on_aspect_gained(_first(5))
	assert_null(bar.scene_at(0), "a manually emptied slot stays empty")
	assert_eq(bar.scene_at(1), _scenes[7], "a swapped slot keeps its pick")
	assert_eq(bar.scene_at(2), _scenes[0])


func test_a_gain_while_full_changes_nothing() -> void:
	var bar := TempQuickbar.new()
	bar.autofill(_first(5))
	watch_signals(bar)
	bar.on_aspect_gained([_scenes[6], _scenes[7]] as Array[PackedScene])
	assert_eq(bar.slots, _first(5))
	assert_signal_not_emitted(bar, "changed")


func test_swap_puts_the_scene_in_the_slot_and_pins_it() -> void:
	var bar := TempQuickbar.new()
	bar.autofill(_first(3))
	watch_signals(bar)
	bar.swap(1, _scenes[6])
	assert_eq(bar.scene_at(1), _scenes[6])
	assert_true(bar.pinned[1])
	assert_false(bar.pinned[0])
	assert_signal_emitted(bar, "changed")


func test_swapping_in_a_kind_already_on_the_bar_exchanges_the_two() -> void:
	var bar := TempQuickbar.new()
	bar.autofill(_first(3))
	bar.swap(0, _scenes[2])
	assert_eq(bar.scene_at(0), _scenes[2])
	assert_eq(bar.scene_at(2), _scenes[0], "the displaced kind moves, never duplicates")


func test_a_fill_emits_changed_once() -> void:
	var bar := TempQuickbar.new()
	watch_signals(bar)
	bar.autofill(_first(3))
	assert_signal_emit_count(bar, "changed", 1)
