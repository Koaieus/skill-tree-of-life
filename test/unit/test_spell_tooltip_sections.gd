extends GutTest

## #764 — the tagline cap and all four marked sections. Cast is fully derived
## ([Targeting]/[NodeTargeting] + [RangeFinder] live under `attack/targeting/`
## and `attack/range_finder/`). On-arrival and Crits are half 2a (#851 landed
## [code]get_description()[/code] on every [OnHitEffect]/[LandingCondition]
## subclass). Then is half 2b (#852 landed every spread's
## [code]get_description()[/code]; [method PropagationConfig.get_description]
## owns the single-target collapse). All four sections are called directly now,
## no has_method duck typing left in `spell_tooltip.gd`.

const _TOOLTIP := preload("res://ui/spell_tooltip/spell_tooltip.tscn")

# show_for() settles its layout over two frames before fading in.
const _SETTLE_FRAMES: int = 5

const _TAGLINE_CAP: int = 80

## ~4 lines at the section's 280px width, ~42 chars/line — proposed default,
## owner-tunable; this test enforces whatever the constant says, never words.
const _SECTION_CAP: int = 170

const _SECTION_NAMES: Array[String] = [
	"%CastSection", "%OnArrivalSection", "%ThenSection", "%CritsSection",
]


func _section_lines(spell: SpellDef, unique_name: String) -> PackedStringArray:
	var tt: SpellTooltip = _TOOLTIP.instantiate()
	add_child_autofree(tt)
	await wait_frames(2)
	tt.show_for(spell, null)
	for _i in _SETTLE_FRAMES:
		await wait_frames(1)
	var section := tt.get_node(unique_name) as SpellTooltipSection
	return section.line_texts()


func _cast_lines(spell: SpellDef) -> PackedStringArray:
	return await _section_lines(spell, "%CastSection")


func _on_arrival_lines(spell: SpellDef) -> PackedStringArray:
	return await _section_lines(spell, "%OnArrivalSection")


func _crits_lines(spell: SpellDef) -> PackedStringArray:
	return await _section_lines(spell, "%CritsSection")


func _then_lines(spell: SpellDef) -> PackedStringArray:
	return await _section_lines(spell, "%ThenSection")


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


## On arrival (#764 half 2a) — every authored spell has at least one
## [OnHitEffect], so the section must never render empty now that #851 landed
## `get_description()` on every subclass.
func test_on_arrival_section_is_never_empty_for_an_authored_spell() -> void:
	for spell in SpellCatalog.ALL:
		var lines := await _on_arrival_lines(spell)
		assert_gt(lines.size(), 0, "%s: On arrival section had no derived content" % spell.id)


## Crits (#764 half 2a) — present iff the spell authors [member SpellDef.crit_conditions],
## never a stray empty section for a spell with none.
func test_crits_section_present_iff_spell_authors_crit_conditions() -> void:
	for spell in SpellCatalog.ALL:
		var lines := await _crits_lines(spell)
		if spell.crit_conditions.is_empty():
			assert_eq(lines.size(), 0, "%s: Crits section should be empty" % spell.id)
		else:
			assert_gt(lines.size(), 0, "%s: Crits section should be non-empty" % spell.id)


## Healing Beam's arrival line names the D-32 heal number through
## [method HealEffect.get_description] — the same fix as
## [method test_healing_beams_cast_section_names_any_node], one section over.
func test_healing_beams_arrival_line_starts_with_heals() -> void:
	var lines := await _on_arrival_lines(SpellCatalog.HEALING_BEAM)
	assert_gt(lines.size(), 0, "fixture: Healing Beam must have an on-arrival line")
	assert_true(
		lines[0].begins_with("Heals"),
		"Healing Beam's arrival line should start with 'Heals', got: %s" % lines[0]
	)


## The D-32 wiring itself: Spark's single [DamageEffect] quotes the impact
## number ([method SpellResolver.impact_damage], no caster board here so the
## default `spell_damage` (1.0) × `power` (1.0) = 1), never the old
## number-free "Deals magic damage." fragment.
func test_on_arrival_line_names_the_impact_damage_number() -> void:
	var spell := SpellCatalog.SPARK
	var expected := SpellResolver.impact_damage(spell, null, null)
	var lines := await _on_arrival_lines(spell)
	assert_eq(lines.size(), 1, "fixture: Spark has exactly one on-hit effect, no reducer")
	assert_string_contains(lines[0], OnHitEffect._fmt_num(expected))


## Then (#764 half 2b) — Spark's propagation authors a filter but no spread
## (single-target by design, see `spark.tres`), so [method PropagationConfig
## .get_description]'s collapse must fire and nothing else may sneak in.
func test_sparks_then_section_is_exactly_the_single_target_line() -> void:
	var lines := await _then_lines(SpellCatalog.SPARK)
	assert_eq(lines, PackedStringArray(["Single target."]))


## Copy budget (#764 half 2b) — each MARKED SECTION's composed text (every
## line joined, matching how a section actually renders) stays within the
## proposed cap over every authored spell. Empty sections (e.g. Crits on a
## spell with no crit_conditions) trivially pass.
func test_every_sections_composed_text_is_within_the_cap() -> void:
	for spell in SpellCatalog.ALL:
		for section_name in _SECTION_NAMES:
			var lines := await _section_lines(spell, section_name)
			var joined := " ".join(lines)
			assert_lt(
				joined.length(), _SECTION_CAP + 1,
				"%s %s: %d chars (cap %d): %s" % [
					spell.id, section_name, joined.length(), _SECTION_CAP, joined
				]
			)
