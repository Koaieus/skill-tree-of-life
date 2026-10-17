extends GutTest

## StatusSections derives an aspect's concept card from the resources that
## describe themselves; ConceptCard renders one SpellTooltipSection per
## non-Summary section. Asserts presence, distinctness and numbers, never a
## literal sentence.

const _CARD := preload("res://ui/concept_card/concept_card.tscn")


func _section(status: StatusDef, title: String) -> SpellSections.Lines:
	for s: Dictionary in StatusSections.build(status):
		if s.title == title:
			return s.lines
	return null


func _status(id: StringName) -> StatusDef:
	return AspectRoster.shared().by_id(id).status


func _text(lines: SpellSections.Lines) -> String:
	return " ".join(lines.lines) if lines != null else ""


func test_every_aspect_has_a_summary_and_a_decay_section() -> void:
	for aspect: Aspect in AspectRoster.shared().aspects:
		if aspect.status == null:
			continue
		var summary := _section(aspect.status, StatusSections.SUMMARY)
		var decay := _section(aspect.status, StatusSections.DECAY)
		assert_true(summary != null and not summary.is_empty(), "%s has a Summary" % aspect.status.id)
		assert_true(decay != null and not decay.is_empty(), "%s has a Decay" % aspect.status.id)


func test_poison_has_no_spread_and_is_resisted_by_poison_resistance() -> void:
	var poison := _status(&"poison")
	assert_null(_section(poison, StatusSections.SPREAD), "poison does not spread")
	assert_eq(_text(_section(poison, StatusSections.RESISTED_BY)), "Poison Resistance")


func test_spreading_statuses_describe_their_spread() -> void:
	for id: StringName in [&"bleeding", &"curse", &"corruption", &"explosive"]:
		var spread := _section(_status(id), StatusSections.SPREAD)
		assert_true(spread != null and not spread.is_empty(), "%s has a Spread section" % id)


func test_a_status_with_no_decay_never_fades_on_its_own() -> void:
	for id: StringName in [&"greed", &"corruption"]:
		var status := _status(id)
		assert_null(status.decay, "%s has no decay" % id)
		assert_string_contains(_text(_section(status, StatusSections.DECAY)), "ever fades")


func test_every_spread_leaf_describes_itself_distinctly_with_its_number() -> void:
	var spill := SpillSpread.new()
	spill.spread_fraction = 0.4
	var sandpile := SandpileSpread.new()
	sandpile.burn = 3
	var explosive := ExplosiveSpread.new()
	explosive.damage_per_charge = 7.0
	var flat := FlatDiffusion.new()
	flat.min_diff = 5
	var fraction := FractionDiffusion.new()
	fraction.fraction = 0.3
	var expect := {spill: "40%", sandpile: "3", explosive: "7", flat: "5", fraction: "30%"}
	var seen := {}
	for leaf: StatusSpread in expect:
		var text := leaf.describe()
		assert_false(text.is_empty(), "%s describes itself" % leaf.get_script().get_global_name())
		assert_string_contains(text, expect[leaf])
		assert_false(seen.has(text), "%s's sentence is its own" % leaf.get_script().get_global_name())
		seen[text] = true


class _SilentSpread:
	extends StatusSpread


func test_a_rule_that_does_not_override_describes_nothing() -> void:
	assert_eq(_SilentSpread.new().describe(), "")


func test_concept_card_supports_aspects_only() -> void:
	assert_true(ConceptCard.supports(load("res://identity/defs/poison.tres")))
	assert_false(ConceptCard.supports(load("res://identity/defs/strength.tres")))
	assert_false(ConceptCard.supports(null))


func test_a_bound_poison_card_instances_one_section_per_built_section() -> void:
	var card: ConceptCard = _CARD.instantiate()
	add_child_autofree(card)
	var poison: Identity = load("res://identity/defs/poison.tres")
	card.bind(poison)
	var built := StatusSections.build(AspectRoster.shared().by_id(poison.id).status)
	var sections := card.find_children("*", "SpellTooltipSection", true, false)
	# The Summary entry renders in the card's summary label, not as a section.
	assert_eq(sections.size(), built.size() - 1)
	assert_false(card.summary_text().is_empty())


func test_a_fraction_decay_reads_as_a_share_not_a_flat_amount() -> void:
	var text := FractionDecay.new(0.25).describe()
	assert_string_contains(text, "25%")
	assert_false(text.contains("0.25"), "not printed as a flat amount: %s" % text)
