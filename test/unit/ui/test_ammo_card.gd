extends GutTest

## #1353 — an ammo card wears its type's status colour as a swatch plus the
## status icon (letter glyph when none), so the cards read apart at a glance.
## Everything derives from the [AmmoType]; a status-less type shows no swatch.

const _CARD_SCENE := preload("res://ui/hud/command_tray/bodies/ammo_card.tscn")
const _ROSTER: AmmoTypeRoster = preload("res://attack/ammo/ammo_type_roster.tres")
const _POISON: AmmoType = preload("res://attack/ammo/types/poison.tres")


func _card(type: AmmoType) -> AmmoCard:
	var card: AmmoCard = _CARD_SCENE.instantiate()
	add_child_autofree(card)
	card.setup(type)
	return card


func test_a_poison_card_shows_a_swatch_in_poisons_hue_and_a_glyph() -> void:
	var card := _card(_POISON)
	var swatch: ColorRect = card.get_node_or_null(^"%Swatch")
	assert_not_null(swatch, "the card has a swatch")
	if swatch == null:
		return
	assert_true(swatch.is_visible_in_tree(), "a status type shows its swatch")
	assert_almost_eq(swatch.color.h, _POISON.first_status_def().tint.h, 0.02, "the swatch is the status hue")
	var icon: TextureRect = card.get_node(^"%StatusIcon")
	var letter: Label = card.get_node(^"%StatusLetter")
	var shows_icon := icon.is_visible_in_tree() and icon.texture != null
	var shows_letter := letter.is_visible_in_tree() and not letter.text.is_empty()
	assert_true(shows_icon or shows_letter, "an icon or a letter glyph names the status")


func test_the_base_arrow_card_shows_no_swatch() -> void:
	var card := _card(_ROSTER.base_type())
	var swatch: ColorRect = card.get_node_or_null(^"%Swatch")
	assert_not_null(swatch, "the card has a swatch node")
	if swatch == null:
		return
	assert_false(swatch.is_visible_in_tree(), "a status-less type shows no swatch")
