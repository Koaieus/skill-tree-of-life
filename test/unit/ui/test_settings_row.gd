extends GutTest

## #609 — a settings row is authored as `settings_row.tscn`, not built as a
## fresh HBoxContainer + Label in `_make_row()`. D2's whole point: the LABEL
## no longer takes the row's slack (`SIZE_EXPAND_FILL`), so a row's control
## sits adjacent to its label at any container width instead of shoved to the
## panel's far right — the defect #606's drone found by screenshot and that
## nothing pinned until now.
##
## D3: the slot's own default (`%Widget` in the row scene) is
## `SIZE_EXPAND_FILL` — a slider or a LineEdit wants the slack. A CheckBox or
## an OptionButton does not, so `_make_widget` overrides those two to
## `SIZE_SHRINK_BEGIN`.

const _MENU_SCENE := preload("res://scenes/meta/settings_menu.tscn")
const _ROW_SCENE := preload("res://scenes/meta/settings_row.tscn")


func _make_menu(width: float) -> SettingsMenu:
	# `menu` (settings_menu.tscn's root) is already anchored full-rect
	# (anchors_preset = 15), so it takes `host`'s size on its own the moment
	# it enters the tree — setting `.size` on it directly, with opposite
	# anchors already non-equal, is what trips Godot's own anchor-conflict
	# warning (surfaced by GUT as an "Unexpected Error").
	var host := Control.new()
	host.size = Vector2(width, 400.0)
	add_child_autofree(host)
	var menu: SettingsMenu = _MENU_SCENE.instantiate()
	host.add_child(menu)
	return menu


func _rows_of(menu: SettingsMenu) -> Array[HBoxContainer]:
	var found: Array[HBoxContainer] = []
	for child in menu.get_node("%Rows").get_children():
		if child is HBoxContainer:
			found.append(child as HBoxContainer)
	return found


func _row_for(menu: SettingsMenu, prop_name: String) -> HBoxContainer:
	for row in _rows_of(menu):
		var label := row.get_node("%Label") as Label
		if label.text == prop_name:
			return row
	return null


# --- acceptance 1: instanced, not built in code -----------------------------

func test_a_row_instances_the_scene_rather_than_building_an_hbox_in_code() -> void:
	var menu := _make_menu(640.0)
	await get_tree().process_frame
	var rows := _rows_of(menu)
	assert_gt(rows.size(), 0, "there are settings to list")
	for row in rows:
		assert_eq(row.scene_file_path, _ROW_SCENE.resource_path,
				"'%s' comes from settings_row.tscn" % row.name)
		assert_not_null(row.get_node_or_null("%Label"), "the scene's label slot")


# --- acceptance 2: the label never takes the slack --------------------------

func test_no_row_label_takes_the_rows_slack() -> void:
	var menu := _make_menu(640.0)
	await get_tree().process_frame
	for row in _rows_of(menu):
		var label := row.get_node("%Label") as Label
		assert_eq(label.size_flags_horizontal & Control.SIZE_EXPAND, 0,
				"'%s' does not expand — #609 D2 inverts this" % label.text)


# --- acceptance 3: the failing test this unit exists to make pass -----------

func test_a_rows_control_sits_adjacent_to_its_label_not_at_the_far_right() -> void:
	for width in [640.0, 900.0]:
		var menu := _make_menu(width)
		await get_tree().process_frame
		var rows := _rows_of(menu)
		assert_gt(rows.size(), 0)
		for row in rows:
			var label := row.get_node("%Label") as Label
			var widget: Control = row.get_child(1)
			var gap: float = widget.position.x - (label.position.x + label.size.x)
			assert_lt(gap, 20.0,
					"at width %d, '%s's control sits right after its label (gap %.1f px) instead of near x=%.1f, the row's far right"
					% [width, label.text, gap, row.size.x])


# --- D3: the two exceptions to the slot's own default ------------------------

func test_a_checkbox_shrinks_instead_of_keeping_the_slots_default() -> void:
	var menu := _make_menu(640.0)
	await get_tree().process_frame
	var row := _row_for(menu, "confirm_islanding_dealloc")
	assert_not_null(row, "GameSettings still has this bool")
	var widget: Control = row.get_child(1)
	assert_true(widget is CheckBox)
	assert_eq(widget.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN,
			"a row-wide invisible hit area is the D3 defect this guards")


func test_an_option_button_shrinks_instead_of_keeping_the_slots_default() -> void:
	var menu := _make_menu(640.0)
	await get_tree().process_frame
	var row := _row_for(menu, "window_mode")
	assert_not_null(row, "GameSettings still has this enum")
	var widget: Control = row.get_child(1)
	assert_true(widget is OptionButton)
	assert_eq(widget.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN,
			"stretching absurdly is the D3 defect this guards")


func test_a_slider_keeps_the_slots_default_expand() -> void:
	var menu := _make_menu(640.0)
	await get_tree().process_frame
	var row := _row_for(menu, "master_volume")
	assert_not_null(row, "GameSettings still has this range")
	var widget: Control = row.get_child(1)
	assert_true(widget is HSlider)
	assert_eq(widget.size_flags_horizontal, Control.SIZE_EXPAND_FILL,
			"sliders DO want the row's slack (#609 D3)")


# --- acceptance 4: every property still lists, sections included ------------

func test_every_setting_and_every_section_header_still_lists() -> void:
	var menu := _make_menu(640.0)
	await get_tree().process_frame
	var section_titles: Array[String] = []
	var row_labels: Array[String] = []
	for child in menu.get_node("%Rows").get_children():
		if child is Label:
			section_titles.append((child as Label).text)
		elif child is HBoxContainer:
			row_labels.append((child.get_node("%Label") as Label).text)

	assert_true(section_titles.has("Audio"))
	assert_true(section_titles.has("Gameplay"))
	assert_true(section_titles.has("Display"))

	var settings: GameSettings = Settings.current
	for prop in settings.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		if prop.usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		assert_true(row_labels.has(String(prop.name)), "'%s' is listed" % prop.name)
