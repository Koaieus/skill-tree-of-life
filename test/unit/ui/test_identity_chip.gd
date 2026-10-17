extends GutTest

## An [IdentityChip] is a dark pill: its border, bare glyph and count all take
## the bound identity's tint lifted through [method Emissive.at] at the chip's
## tier; each chip owns its own stylebox; a null identity still shows the count.

const _CHIP_SCENE := preload("res://ui/identity_badge/identity_chip.tscn")
const _POISON := preload("res://effects/status/poison.tres")
const _BLEEDING := preload("res://effects/status/bleeding.tres")


func _chip(of: Identity, count: int) -> IdentityChip:
	var chip: IdentityChip = _CHIP_SCENE.instantiate()
	add_child_autofree(chip)
	chip.bind(of, count)
	return chip


func _lit(chip: IdentityChip, of: Identity) -> Color:
	return Emissive.at(of.tint, Emissive.stops(chip.emissive_tier))


func _style(chip: IdentityChip) -> StyleBoxFlat:
	return chip.get_theme_stylebox(&"panel") as StyleBoxFlat


func _count(chip: IdentityChip) -> Label:
	return chip.get_node(^"%Count") as Label


func _glyph(chip: IdentityChip) -> TextureRect:
	return chip.get_node(^"%Glyph") as TextureRect


func test_binding_poison_with_four_reads_four() -> void:
	assert_eq(_count(_chip(_POISON.identity, 4)).text, "4")


func test_border_count_and_glyph_take_the_lit_tint() -> void:
	var chip := _chip(_POISON.identity, 4)
	var lit := _lit(chip, _POISON.identity)
	var style := _style(chip)
	assert_not_null(style, "the chip paints a StyleBoxFlat panel")
	if style == null:
		return
	assert_eq(style.border_color, lit, "the border is the lit tint")
	assert_eq(_count(chip).get_theme_color(&"font_color"), lit, "the count is the lit tint")
	assert_eq(_glyph(chip).self_modulate, lit, "the glyph is the lit tint")


func test_the_glyph_texture_follows_glyph_px() -> void:
	var chip := _chip(_POISON.identity, 4)
	var texture := _glyph(chip).texture
	assert_not_null(texture, "a bound identity shows its glyph")
	if texture == null:
		return
	assert_eq(texture.get_width(), chip.glyph_px, "the glyph is baked at glyph_px")
	chip.glyph_px = 32
	assert_eq(_glyph(chip).texture.get_width(), 32, "a glyph_px change re-bakes the glyph")


func test_the_chip_holds_no_framed_badge() -> void:
	var chip := _chip(_POISON.identity, 4)
	assert_eq(chip.find_children("*", "IdentityBadge", true, false).size(), 0, "the pill border is the only frame")


func test_two_chips_never_share_a_stylebox() -> void:
	var poison := _chip(_POISON.identity, 4)
	var bleeding := _chip(_BLEEDING.identity, 2)
	assert_ne(_style(poison), _style(bleeding), "each chip owns its stylebox")
	assert_ne(_style(poison).border_color, _style(bleeding).border_color, "so each border keeps its own tint")


func test_a_null_identity_still_shows_the_count() -> void:
	var chip := _chip(null, 3)
	assert_eq(_count(chip).text, "3", "the count shows alone")
	assert_null(_glyph(chip).texture, "no identity, no glyph")


func test_a_bind_before_entering_the_tree_keeps_the_count() -> void:
	var chip: IdentityChip = _CHIP_SCENE.instantiate()
	chip.bind(_POISON.identity, 4)
	add_child_autofree(chip)
	assert_eq(_count(chip).text, "4", "a bind before add_child still shows its count")
