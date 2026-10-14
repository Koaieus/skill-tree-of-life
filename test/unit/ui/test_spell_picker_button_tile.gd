extends GutTest

## A spell picker tile draws its spell's icon full-bleed (no [IdentityBadge]
## for the spell), falls back to the noun letter, and lists each innate
## affinity as an [InnateChip] (aspect badge + count) under the name; a non-1
## ingest rate is named in the hover tooltip only.

const _BUTTON_SCENE := preload("res://ui/spell_picker_bar/spell_picker_button.tscn")
const _VENOM_BURST := preload("res://attack/spell/defs/venom_burst.tres")
const _POISON := preload("res://effects/status/poison.tres")
const _BLEEDING := preload("res://effects/status/bleeding.tres")


func _button(spell: SpellDef) -> SpellPickerButton:
	var button: SpellPickerButton = _BUTTON_SCENE.instantiate()
	button.spell = spell
	add_child_autofree(button)
	return button


func _intake(status: StatusDef, innate: int, gain := 1) -> AspectIntake:
	var affinity := AspectIntake.new()
	affinity.identity = status.identity
	affinity.innate = innate
	affinity.affinity_gain = gain
	return affinity


func _spell(affinities: Array[AspectIntake], icon: Texture2D = null) -> SpellDef:
	var spell := SpellDef.new()
	spell.name = "Zap"
	spell.identity = IdentityFixture.of(Color(0.4, 0.8, 1.0), &"zap", Identity.Kind.SPELL)
	spell.identity.noun = "Zap"
	spell.identity.icon = icon
	spell.intakes = affinities
	return spell


func _chips(button: SpellPickerButton) -> Array[InnateChip]:
	var out: Array[InnateChip] = []
	for child in button.get_node(^"%InnateChips").get_children():
		if child is InnateChip and not child.is_queued_for_deletion():
			out.append(child)
	return out


func _chip_text(chip: InnateChip) -> String:
	return (chip.get_node(^"%Count") as Label).text


func _chip_aspect(chip: InnateChip) -> StringName:
	var identity := (chip.get_node(^"%Badge") as IdentityBadge).identity
	return identity.id if identity != null else &""


func test_the_tile_draws_the_spell_icon_full_bleed_and_has_no_spell_badge() -> void:
	var button := _button(_VENOM_BURST)
	await get_tree().process_frame
	var icon := button.get_node(^"%Icon") as TextureRect
	assert_not_null(icon, "the tile has an %Icon TextureRect")
	if icon == null:
		return
	assert_eq(icon.texture, _VENOM_BURST.identity.icon, "the icon is the spell identity's")
	assert_true(icon.visible, "an iconed spell shows its icon")
	assert_eq(icon.expand_mode, TextureRect.EXPAND_IGNORE_SIZE, "the icon fills its square, never its texture size")
	assert_eq(icon.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "kept aspect, centred")
	assert_gt(minf(icon.size.x, icon.size.y), 32.0, "the icon square is laid out large")
	var chips := button.get_node(^"%InnateChips")
	for badge in button.find_children("*", "IdentityBadge", true, false):
		assert_true(chips.is_ancestor_of(badge), "the only badges are the innate chips', never the spell's")


func test_venom_burst_shows_one_poison_chip_of_fifteen() -> void:
	var chips := _chips(_button(_VENOM_BURST))
	assert_eq(chips.size(), 1, "one innate entry, one chip")
	if chips.is_empty():
		return
	assert_eq(_chip_aspect(chips[0]), &"poison", "the chip's badge is poison")
	assert_eq(_chip_text(chips[0]), "15", "the chip reads the innate count")


func test_two_innate_entries_show_two_chips_in_affinity_order() -> void:
	var chips := _chips(_button(_spell([_intake(_BLEEDING, 3), _intake(_POISON, 7)])))
	assert_eq(chips.size(), 2, "two chips")
	if chips.size() < 2:
		return
	assert_eq([_chip_aspect(chips[0]), _chip_text(chips[0])], [&"bleeding", "3"], "first entry first")
	assert_eq([_chip_aspect(chips[1]), _chip_text(chips[1])], [&"poison", "7"], "second entry second")


func test_no_innate_entries_leave_an_empty_hidden_row() -> void:
	var button := _button(_spell([_intake(_POISON, 0, 0)]))
	assert_eq(_chips(button).size(), 0, "a refused aspect with no innate shows nothing")
	assert_false((button.get_node(^"%InnateChips") as Control).visible, "the empty row hides")


func test_respelling_rebuilds_the_chips() -> void:
	var button := _button(_VENOM_BURST)
	button.spell = _spell([_intake(_BLEEDING, 3), _intake(_POISON, 7)])
	assert_eq(_chips(button).size(), 2, "the old chip is gone, the new two are in")
	button.spell = null
	assert_eq(_chips(button).size(), 0, "no spell, no chips")


func test_the_tooltip_names_each_non_one_rate() -> void:
	var button := _button(_spell([_intake(_POISON, 7, 2), _intake(_BLEEDING, 0, 0), _intake(_BLEEDING, 1)]))
	assert_string_contains(button.tooltip_text, "poison ×2")
	assert_string_contains(button.tooltip_text, "bleeding ×0")
	assert_eq(button.tooltip_text.count("×"), 2, "a rate of 1 is not listed")
	button.spell = _spell([_intake(_POISON, 7)])
	assert_eq(button.tooltip_text, "", "all-default rates leave no tooltip")


func test_an_iconless_spell_shows_its_noun_letter() -> void:
	var button := _button(_spell([]))
	var letter := button.get_node(^"%Letter") as Label
	assert_not_null(letter, "the tile has a %Letter fallback")
	if letter == null:
		return
	assert_true(letter.visible, "no icon → the letter shows")
	assert_eq(letter.text, "Z", "the noun's first letter")
	assert_false((button.get_node(^"%Icon") as TextureRect).visible, "and the icon hides")
