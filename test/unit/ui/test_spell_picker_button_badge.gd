extends GutTest

## A spell picker button shows its spell as an [IdentityBadge] bound to
## [member SpellDef.identity] — with no icon the badge draws the noun letter;
## the button keeps no letter fallback of its own.

const _BUTTON_SCENE := preload("res://ui/spell_picker_bar/spell_picker_button.tscn")


func _button(spell: SpellDef) -> SpellPickerButton:
	var button: SpellPickerButton = _BUTTON_SCENE.instantiate()
	button.spell = spell
	add_child_autofree(button)
	return button


func test_an_iconless_spell_shows_its_identity_badge_and_no_letter_label() -> void:
	var spell := SpellDef.new()
	spell.name = "Zap"
	spell.identity = IdentityFixture.of(Color(0.4, 0.8, 1.0), &"zap", Identity.Kind.SPELL)
	var button := _button(spell)
	var badges := button.find_children("*", "IdentityBadge", true, false)
	assert_eq(badges.size(), 1, "one identity badge")
	if not badges.is_empty():
		assert_eq((badges[0] as IdentityBadge).identity, spell.identity, "bound to the spell identity")
	assert_null(button.find_child("LetterLabel", true, false), "no letter label of its own")


func test_a_cleared_spell_unbinds_the_badge() -> void:
	var spell := SpellDef.new()
	spell.identity = IdentityFixture.of(Color.RED, &"zap", Identity.Kind.SPELL)
	var button := _button(spell)
	button.spell = null
	var badges := button.find_children("*", "IdentityBadge", true, false)
	assert_eq(badges.size(), 1, "one identity badge")
	if not badges.is_empty():
		assert_null((badges[0] as IdentityBadge).identity, "no spell, no identity")
