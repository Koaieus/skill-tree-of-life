extends GutTest

## [SpellStatRow] exists to be *authored* — every field is an export with a
## push-setter so a row can be tuned in the inspector, and [method
## SpellStatRow.bind] is the same thing from code. Both paths are load-bearing,
## so both are covered here, along with the scene-authored-override ordering
## that [PanelHeader] documents (setters fire before the @onready refs exist).

const _ROW := preload("res://ui/spell_tooltip/spell_stat_row.tscn")

const _NO_ACCENT := Color(1.0, 1.0, 1.0, 0.0)


func _row() -> SpellStatRow:
	var row: SpellStatRow = _ROW.instantiate()
	add_child_autofree(row)
	return row


func test_bind_fills_both_labels() -> void:
	var row := _row()
	row.bind("Damage", "24")
	assert_eq(row.get_node("%NameLabel").text, "Damage")
	assert_eq(row.get_node("%ValueLabel").text, "24")


func test_scene_authored_exports_survive_ready() -> void:
	# The .tscn authors row_label/value on the root; the setters run before the
	# @onready Labels exist and skip their push, so _ready() must re-apply them.
	var row := _row()
	assert_eq(row.get_node("%NameLabel").text, row.row_label)
	assert_eq(row.get_node("%ValueLabel").text, row.value)


func test_no_accent_leaves_the_value_on_the_theme_reading() -> void:
	var row := _row()
	row.bind("Target", "Enemy-occupied node")
	assert_false(
		row.get_node("%ValueLabel").has_theme_color_override(&"font_color"),
		"an alpha-0 accent should not override the TierValue colour"
	)


func test_accent_is_raised_to_an_emissive_tier() -> void:
	var row := _row()
	var accent := Color(1.0, 0.85, 0.4)
	row.bind("Hops", "7", accent, true)
	var value: Label = row.get_node("%ValueLabel")
	assert_eq(
		value.get_theme_color(&"font_color"),
		Emissive.at(accent, Emissive.VALUE),
		"emphasis should light the accent at the VALUE tier"
	)
	# Same accent without emphasis drops a tier — quieter, still tinted.
	row.emphasis = false
	assert_eq(value.get_theme_color(&"font_color"), Emissive.at(accent, Emissive.LABEL))


func test_emphasis_bumps_the_authored_font_size() -> void:
	var row := _row()
	var value: Label = row.get_node("%ValueLabel")
	var base := value.get_theme_font_size(&"font_size")
	row.bind("Damage", "24", Color(1.0, 0.85, 0.4), true)
	assert_eq(value.get_theme_font_size(&"font_size"), base + row.emphasis_size_bump)
	row.emphasis = false
	assert_eq(value.get_theme_font_size(&"font_size"), base, "size bump should lift")


func test_stat_id_takes_name_and_accent_from_the_stat_def() -> void:
	var row := _row()
	row.stat_id = &"mana"
	var def := StatRegistry.get_def(&"mana")
	assert_eq(row.get_node("%NameLabel").text, def.display_name)
	assert_eq(row.accent_color, def.tint_color, "accent should come from StatDef.tint_color")
