extends GutTest

## [LobbyOptionSet] and [OptionChoiceRow] — the lobby's run-section ladders
## (#642/#643). Pure state, on hand-built sets rather than the authored
## `lobby_options/*.tres`: the owner authors those ladders, and what is pinned
## here is what any ladder is promised.

const _ROW := preload("res://ui/frontmatter/panels/option_choice_row.tscn")


func _option(label: String, patch_count: int = 1) -> LobbyOption:
	var o := LobbyOption.new()
	o.label = label
	for i in patch_count:
		o.patches.append(ScenarioOverride.new())
	return o


func _option_set(options: Array, default_index: int = -1) -> LobbyOptionSet:
	var s := LobbyOptionSet.new()
	for o in options:
		s.options.append(o)
	s.default_index = default_index
	return s


# --- LobbyOptionSet ---------------------------------------------------------

func test_choices_drops_null_slots_and_keeps_authored_order() -> void:
	var s := _option_set([_option("S"), null, _option("M"), _option("L")])
	var labels: Array[String] = []
	for c in s.choices():
		labels.append(c.label)
	assert_eq(labels, ["S", "M", "L"] as Array[String])


func test_patches_at_indexes_into_choices_not_options() -> void:
	# An authored null slot must not shift what a pick resolves to.
	var m := _option("M", 2)
	var s := _option_set([_option("S"), null, m])
	assert_eq(s.patches_at(1), m.patches, "index 1 of choices is M, past the null")
	assert_eq(s.patches_at(1).size(), 2)


func test_patches_at_out_of_range_is_nothing_picked() -> void:
	var s := _option_set([_option("S"), _option("M")])
	assert_eq(s.patches_at(-1).size(), 0)
	assert_eq(s.patches_at(2).size(), 0)
	assert_eq(_option_set([]).patches_at(0).size(), 0)


# --- OptionChoiceRow --------------------------------------------------------

func _row() -> OptionChoiceRow:
	var r: OptionChoiceRow = _ROW.instantiate()
	add_child_autofree(r)
	return r


func test_a_null_or_empty_set_leaves_the_row_hidden() -> void:
	var r := _row()
	r.set_choices("Size", null)
	assert_false(r.visible, "null set: the policy did not unlock this knob")
	r.set_choices("Size", _option_set([]))
	assert_false(r.visible, "empty set: nothing to list")
	r.set_choices("Size", _option_set([null]))
	assert_false(r.visible, "a set of only null slots lists nothing")


func test_a_ladder_shows_the_row_with_its_authored_default_selected() -> void:
	var r := _row()
	r.set_choices("Size", _option_set([_option("S"), _option("M"), _option("L")], 1))
	assert_true(r.visible)
	assert_eq(r.get_value(), 1, "the authored default is shown")


func test_an_out_of_range_default_falls_back_to_blank() -> void:
	var r := _row()
	r.set_choices("Size", _option_set([_option("S"), _option("M")], 5))
	assert_eq(r.get_value(), -1)


func test_showing_a_default_or_restoring_a_pick_is_not_a_pick() -> void:
	var r := _row()
	var picks: Array[int] = []
	r.option_picked.connect(func(i: int) -> void: picks.append(i))
	r.set_choices("Size", _option_set([_option("S"), _option("M")], 0))
	r.set_value(1)
	assert_eq(picks.size(), 0, "#643 acceptance 5: an untouched row reports nothing")
	assert_eq(r.get_value(), 1, "but the restored pick is what the widget shows")
