extends GutTest

## [BadgeText] resolves `{id}` tokens in authored text to an inline badge plus
## the identity's noun; [method BadgeText.strip] is the plain-text twin. Reads
## the shipped identity roster (`poison`) and the `poison_aspect` StatDef.

var _label: RichTextLabel


func before_each() -> void:
	BadgeText.clear_warnings()
	_label = RichTextLabel.new()
	add_child_autofree(_label)


## What one `add_image` item contributes to `get_parsed_text()` on this engine
## (a single space in 4.7) — probed, so the exact-equality asserts below pin
## exactly one image: a second would add a second placeholder.
func _image_placeholder() -> String:
	var probe := RichTextLabel.new()
	add_child_autofree(probe)
	probe.add_image(PlaceholderTexture2D.new(), 8, 8)
	return probe.get_parsed_text()


func test_token_renders_badge_then_noun() -> void:
	BadgeText.render(_label, "applies 2 {poison} stacks")
	var glyph := _image_placeholder()
	assert_eq(glyph.length(), 1, "an image is one placeholder character")
	assert_eq(_label.get_parsed_text(), "applies 2 " + glyph + "\u00A0Poison stacks")


func test_unknown_token_verbatim_and_warns_once() -> void:
	BadgeText.render(_label, "{nope}")
	assert_eq(_label.get_parsed_text(), "{nope}")
	assert_push_warning_count(1)
	BadgeText.render(_label, "{nope}")
	assert_eq(_label.get_parsed_text(), "{nope}")
	assert_push_warning_count(1, "second render of the same unknown id stays silent")


func test_strip_resolves_stat_id_to_its_identity_noun() -> void:
	assert_eq(BadgeText.strip("+1 {poison_aspect}"), "+1 Poison")


func test_token_inside_bbcode_is_rendered_inside_the_tag() -> void:
	BadgeText.render(_label, "[b]{poison}[/b]")
	var parsed := _label.get_parsed_text()
	assert_false(parsed.contains("[b]") or parsed.contains("[/b]"), "tags parsed, not literal")
	assert_false(parsed.contains("{poison}"), "token resolved")
	assert_eq(parsed, _image_placeholder() + "\u00A0Poison")


func test_amount_token_strips_to_amount_then_noun() -> void:
	assert_eq(BadgeText.strip("applies {poison:4} stacks"), "applies 4 Poison stacks")


func test_amount_token_renders_amount_badge_noun_unbroken() -> void:
	BadgeText.render(_label, "applies {poison:4} stacks")
	assert_eq(_label.get_parsed_text(),
			"applies 4 " + _image_placeholder() + " Poison stacks")


func test_a_concept_carries_a_hint_a_stat_does_not() -> void:
	var poison := IdentityRoster.shared().by_id(&"poison")
	assert_eq(BadgeText.hint_of(poison), BadgeText.HINT_PREFIX + "poison")
	var strength := StatRegistry.get_def(&"strength")
	assert_not_null(strength, "guard: strength is a stat")
	if strength == null:
		return
	assert_not_null(strength.identity, "guard: strength has an identity")
	assert_eq(BadgeText.hint_of(strength.identity), "", "no concept card, no hint")


func test_badge_label_plain_text_is_the_strip() -> void:
	var label := BadgeLabel.new()
	add_child_autofree(label)
	label.badge_text = "applies {poison:4} stacks"
	assert_eq(label.plain_text(), "applies 4 Poison stacks")


func test_badge_label_tooltip_is_the_concept_card() -> void:
	var label := BadgeLabel.new()
	add_child_autofree(label)
	var card = label._make_custom_tooltip(BadgeText.HINT_PREFIX + "poison")
	assert_true(card is ConceptCard, "a concept hint builds the card")
	if card is ConceptCard:
		assert_eq(card.identity.id, &"poison")
		card.free()
	assert_null(label._make_custom_tooltip("anything else"), "the engine default")
