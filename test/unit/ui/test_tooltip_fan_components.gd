extends GutTest

## Tooltip V2 (#293) — shared row components acceptance test. Each component
## instantiates standalone (no TooltipFan present) and renders from injected
## data. See docs/domain/tooltip-fan.md for the shared progress(0..1) clock
## contract every component here implements.

const _PANEL_HEADER_SCENE := preload("res://ui/tooltip_fan/panel_header.tscn")
const _STAT_VALUE_ROW_SCENE := preload("res://ui/tooltip_fan/stat_value_row.tscn")
const _ADDON_ITEM_SCENE := preload("res://ui/tooltip_fan/addon_item.tscn")


func _stat_def(id: StringName, display: String, tint: Color) -> StatDef:
	var d := StatDef.new()
	d.id = id
	d.display_name = display
	d.tint_color = tint
	return d


func _no_mods() -> Array[StatModifier]:
	return []


func _modifier(op: StatModifier.Operation, value: float, stat_id: StringName = &"armor") -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = op
	m.value = value
	return m


# ─── PanelHeader ────────────────────────────────────────────────────────────

func test_panel_header_renders_header_and_subheader() -> void:
	var header := _PANEL_HEADER_SCENE.instantiate()
	add_child_autofree(header)
	header.bind("owner", "level 4 warlock")
	assert_eq(header._header_label.text, "OWNER")
	assert_eq(header._subheader_label.text, "level 4 warlock")
	assert_true(header._subheader_label.visible)


func test_panel_header_empty_subheader_collapses() -> void:
	var header := _PANEL_HEADER_SCENE.instantiate()
	add_child_autofree(header)
	header.bind("owner")
	assert_false(header._subheader_label.visible)


func test_panel_header_empty_subheader_occupies_header_height_only() -> void:
	var with_sub := _PANEL_HEADER_SCENE.instantiate()
	add_child_autofree(with_sub)
	with_sub.bind("owner", "subtext")

	var without_sub := _PANEL_HEADER_SCENE.instantiate()
	add_child_autofree(without_sub)
	without_sub.bind("owner")

	await get_tree().process_frame
	# Compare MINIMUM size, not `size`. Both headers are parented to the test
	# node rather than to a container, and Godot only ever grows a free-standing
	# Control's `size` up to its minimum — it never shrinks it back down. So
	# both instances kept whatever height they were first laid out at and the
	# `size.y` comparison could not observe the collapse it was written for.
	# `get_combined_minimum_size()` is what the VBoxContainer actually reports
	# to its parent, and it's the quantity the "no reserved blank line" claim
	# is about: a hidden child contributes nothing to a VBox's minimum.
	assert_lt(without_sub.get_combined_minimum_size().y, with_sub.get_combined_minimum_size().y,
		"collapsed subheader must not reserve a blank line's height")


func test_panel_header_progress_animates_scale_and_fade() -> void:
	var header := _PANEL_HEADER_SCENE.instantiate()
	add_child_autofree(header)
	header.start_scale = 0.9
	header.set_progress(0.0)
	assert_almost_eq(header.scale.x, 0.9, 0.001)
	assert_almost_eq(header.modulate.a, 0.0, 0.001)
	header.set_progress(1.0)
	assert_almost_eq(header.scale.x, 1.0, 0.001)
	assert_almost_eq(header.modulate.a, 1.0, 0.001)


# ─── StatValueRow ───────────────────────────────────────────────────────────

func test_stat_value_row_scalar_form() -> void:
	var row := _STAT_VALUE_ROW_SCENE.instantiate()
	add_child_autofree(row)
	var def := _stat_def(&"str", "Strength", Color.RED)
	row.bind_scalar(def, 5.0)
	assert_eq(row._name_label.text, "Strength")
	assert_eq(row._value_label.text, "+5")


func test_stat_value_row_scalar_form_keeps_negative_sign() -> void:
	var row := _STAT_VALUE_ROW_SCENE.instantiate()
	add_child_autofree(row)
	var def := _stat_def(&"str", "Strength", Color.RED)
	row.bind_scalar(def, -3.0)
	assert_eq(row._value_label.text, "-3")


func test_stat_value_row_pool_form() -> void:
	var row := _STAT_VALUE_ROW_SCENE.instantiate()
	add_child_autofree(row)
	var def := _stat_def(&"hp", "HP", Color.RED)
	row.bind_pool(def, 6.0, 10.0)
	assert_eq(row._value_label.text, "6 / 10")


func test_stat_value_row_parenthetical_form() -> void:
	var row := _STAT_VALUE_ROW_SCENE.instantiate()
	add_child_autofree(row)
	var def := _stat_def(&"armor", "Armor", Color.RED)
	row.bind_parenthetical(def, 5.0, 3.0)
	assert_eq(row._value_label.text, "5 (3)")


func test_stat_value_row_int_stat_rounds_a_scaled_fraction() -> void:
	# #622 — the observed bug: an aura's distance-falloff scaling can hand an
	# INT-typed stat a fractional value (39.97). Display must round it, never
	# print the fraction.
	var row := _STAT_VALUE_ROW_SCENE.instantiate()
	add_child_autofree(row)
	var def := _stat_def(&"strength", "Strength", Color.RED)
	def.value_type = StatDef.ValueType.INT
	row.bind_scalar(def, 39.97)
	assert_eq(row._value_label.text, "+40")


func test_stat_value_row_float_stat_keeps_decimals() -> void:
	var row := _STAT_VALUE_ROW_SCENE.instantiate()
	add_child_autofree(row)
	var def := _stat_def(&"crit_chance", "Crit Chance", Color.RED)
	def.value_type = StatDef.ValueType.FLOAT
	row.bind_scalar(def, 1.5)
	assert_eq(row._value_label.text, "+1.5")


func test_stat_value_row_tints_name_by_stat_def() -> void:
	var row := _STAT_VALUE_ROW_SCENE.instantiate()
	add_child_autofree(row)
	var tint := Color(0.29, 0.59, 1.0)
	var def := _stat_def(&"int", "Intelligence", tint)
	row.bind_scalar(def, 2.0)
	assert_eq(row._name_label.get_theme_color("font_color"), tint)


func test_stat_value_row_icon_slot_exists_and_is_hidden() -> void:
	var row := _STAT_VALUE_ROW_SCENE.instantiate()
	add_child_autofree(row)
	assert_not_null(row._icon)
	assert_true(row._icon is TextureRect)
	assert_false(row._icon.visible)


func test_stat_value_row_progress_animates_scale_and_fade() -> void:
	var row := _STAT_VALUE_ROW_SCENE.instantiate()
	add_child_autofree(row)
	row.start_scale = 0.9
	row.set_progress(0.0)
	assert_almost_eq(row.scale.x, 0.9, 0.001)
	assert_almost_eq(row.modulate.a, 0.0, 0.001)
	row.set_progress(1.0)
	assert_almost_eq(row.scale.x, 1.0, 0.001)
	assert_almost_eq(row.modulate.a, 1.0, 0.001)


# ─── AddonItem ──────────────────────────────────────────────────────────────

func test_addon_item_shows_title_and_icon_with_no_modifiers_or_description() -> void:
	var item := _ADDON_ITEM_SCENE.instantiate()
	add_child_autofree(item)
	item.bind("Bunker Plating", _no_mods())
	assert_eq(item._title_label.text, "Bunker Plating")
	assert_true(item._icon.visible, "icon is always shown, even for a bare named item")
	assert_not_null(item._icon.texture, "placeholder texture ships until #281 lands")
	assert_false(item._modifier_rows.visible, "no modifiers collapses the modifier block")
	assert_false(item._description_label.visible, "no description hides the description tag")


func test_addon_item_renders_one_mod_slab_row_per_modifier() -> void:
	var item := _ADDON_ITEM_SCENE.instantiate()
	add_child_autofree(item)
	var mods: Array[StatModifier] = [
		_modifier(StatModifier.Operation.ADD_BASE, 5.0, &"armor"),
		_modifier(StatModifier.Operation.INCREASE, 20.0, &"armor"),
	]
	item.bind("Bunker Plating", mods)
	assert_true(item._modifier_rows.visible)
	assert_eq(item._modifier_rows.get_child_count(), 2)
	for child in item._modifier_rows.get_children():
		assert_true(child is ModSlabRow)


func test_addon_item_shows_description_when_present() -> void:
	var item := _ADDON_ITEM_SCENE.instantiate()
	add_child_autofree(item)
	item.bind("Bunker Plating", _no_mods(), "Grants a flat armor bonus.")
	assert_true(item._description_label.visible)
	assert_eq(item._description_label.text, "Grants a flat armor bonus.")


func test_addon_item_rebind_clears_previous_modifier_rows() -> void:
	var item := _ADDON_ITEM_SCENE.instantiate()
	add_child_autofree(item)
	var mods: Array[StatModifier] = [_modifier(StatModifier.Operation.ADD_BASE, 5.0)]
	item.bind("First", mods)
	assert_eq(item._modifier_rows.get_child_count(), 1)
	item.bind("Second", _no_mods())
	assert_eq(item._modifier_rows.get_child_count(), 0)
	assert_false(item._modifier_rows.visible)


func test_addon_item_progress_animates_scale_and_fade() -> void:
	var item := _ADDON_ITEM_SCENE.instantiate()
	add_child_autofree(item)
	item.start_scale = 0.9
	item.set_progress(0.0)
	assert_almost_eq(item.scale.x, 0.9, 0.001)
	assert_almost_eq(item.modulate.a, 0.0, 0.001)
	item.set_progress(1.0)
	assert_almost_eq(item.scale.x, 1.0, 0.001)
	assert_almost_eq(item.modulate.a, 1.0, 0.001)
