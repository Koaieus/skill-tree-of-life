@tool
extends GutTest

## [SpellSections] on-arrival: the spell's own effect lines, then one line per
## [SpellAffinity] — a status spell's "Applies X (N per hit" line is its
## affinity's now, read through the same stacks fold the landing uses.

const _VENOM := preload("res://attack/spell/defs/venom_burst.tres")
const _HEX := preload("res://attack/spell/defs/hex.tres")
const _DAZZLE := preload("res://attack/spell/defs/dazzle.tres")
const _SUNDER := preload("res://attack/spell/defs/sunder.tres")


func _arrival(def: SpellDef) -> Array:
	return Array(SpellSections.build(def).on_arrival.lines)


func _has_prefix(lines: Array, prefix: String) -> bool:
	for line in lines:
		if String(line).begins_with(prefix):
			return true
	return false


func test_venom_burst_reads_applies_poison_innate_per_hit() -> void:
	var lines := _arrival(_VENOM)
	var innate: int = _VENOM.affinities[0].innate
	assert_true(_has_prefix(lines, "Applies Poison (%d per hit" % innate), "the dose's line: %s" % str(lines))
	assert_true(lines.has("Applies Poison (%d per hit; +2 per poison infused)." % innate), str(lines))


func test_the_affinity_line_follows_the_damage_line() -> void:
	var lines := _arrival(_VENOM)
	var poison_at := -1
	for i in lines.size():
		if String(lines[i]).begins_with("Applies Poison"):
			poison_at = i
	assert_gt(poison_at, 0, "damage line first, then the affinity: %s" % str(lines))


func test_every_template_spell_reads_its_innate_count() -> void:
	assert_true(_has_prefix(_arrival(_HEX), "Applies Curse (5 per hit"), str(_arrival(_HEX)))
	assert_true(_has_prefix(_arrival(_DAZZLE), "Applies Blindness (3 per hit"), str(_arrival(_DAZZLE)))
	assert_true(_has_prefix(_arrival(_SUNDER), "Applies Armor Break (2 per hit"), str(_arrival(_SUNDER)))
