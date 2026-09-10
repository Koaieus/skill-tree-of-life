extends GutTest

## #764 — the tagline cap and the Cast section, which is fully derived today
## ([Targeting]/[NodeTargeting] + [RangeFinder] live under `attack/targeting/`
## and `attack/range_finder/`, both landed in this branch).
##
## On-arrival / Then / Crits are deliberately NOT pinned here yet: their
## describers live on [OnHitEffect] / crit-condition / [PropagationConfig]
## subclasses that #850-852 are still rewriting onto the final
## `LandingCondition`/`ScaleDamageEffect` shape (hub #849, "Refactor first").
## [SpellTooltip] reads whatever `get_description()` those already expose via
## duck typing (see `_populate_on_arrival_section` etc.), so pinning their
## copy now would just get re-broken under a live rebase. Follow-up tracked
## on #764 directly.

const _TOOLTIP := preload("res://ui/spell_tooltip/spell_tooltip.tscn")

# show_for() settles its layout over two frames before fading in.
const _SETTLE_FRAMES: int = 5

const _TAGLINE_CAP: int = 80


func _cast_lines(spell: SpellDef) -> PackedStringArray:
	var tt: SpellTooltip = _TOOLTIP.instantiate()
	add_child_autofree(tt)
	await wait_frames(2)
	tt.show_for(spell, null)
	for _i in _SETTLE_FRAMES:
		await wait_frames(1)
	var section := tt.get_node("%CastSection") as SpellTooltipSection
	return section.line_texts()


func test_every_authored_tagline_is_within_the_cap() -> void:
	for spell in SpellCatalog.ALL:
		assert_lt(
			spell.tagline.length(), _TAGLINE_CAP + 1,
			"%s: tagline is %d chars, cap is %d" % [spell.id, spell.tagline.length(), _TAGLINE_CAP]
		)


func test_every_authored_spell_has_a_tagline() -> void:
	for spell in SpellCatalog.ALL:
		assert_false(spell.tagline.is_empty(), "%s: no tagline authored" % spell.id)


func test_cast_section_is_never_empty_for_an_authored_spell() -> void:
	for spell in SpellCatalog.ALL:
		var lines := await _cast_lines(spell)
		assert_gt(lines.size(), 0, "%s: Cast section had no derived content" % spell.id)


## LAN-08 bug fixed by this issue: Healing Beam authors `ownership_filter =
## Any` (heals either side on purpose — see `node_targeting.gd`'s top
## docstring) and used to fall through to the generic "Single node" line.
func test_healing_beams_cast_section_names_any_node() -> void:
	var lines := await _cast_lines(SpellCatalog.HEALING_BEAM)
	var joined := " ".join(lines)
	assert_string_contains(joined.to_lower(), "any node")


func test_no_section_text_contains_the_long_form_description() -> void:
	for spell in SpellCatalog.ALL:
		if spell.description.is_empty():
			continue
		var lines := await _cast_lines(spell)
		for line in lines:
			assert_eq(
				line.find(spell.description), -1,
				"%s: Cast section leaked the long description" % spell.id
			)
