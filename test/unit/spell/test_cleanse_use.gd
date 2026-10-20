extends GutTest

## [CleanseUse]'s shared-copy contract at the bag: every row pointing at one
## [CleanseEffect] template writes into ONE per-cast copy, distinct templates
## get distinct copies, and the template itself is never mutated.

const _DEF_PATH := "res://attack/spell/defs/absolution.tres"
const _CORRUPTION: StatusDef = preload("res://effects/status/corruption.tres")
const _CURSE: StatusDef = preload("res://effects/status/curse.tres")

var _def: SpellDef


func before_each() -> void:
	_def = load(_DEF_PATH) as SpellDef


func _template() -> CleanseEffect:
	return (_def.intakes[0].use as CleanseUse).effect


func _use_of(template: CleanseEffect) -> CleanseUse:
	var use := CleanseUse.new()
	use.effect = template
	return use


func test_two_rows_on_one_template_share_one_copy_at_their_innate_loads() -> void:
	var riders := Infusion.innate(_def).bag(_def).riders
	assert_eq(riders.size(), 1, "one shared effect for both rows")
	if riders.size() != 1:
		return
	var copy := riders[0] as CleanseEffect
	assert_not_null(copy, "the rider is a CleanseEffect")
	if copy == null:
		return
	assert_eq(copy.template, _template(), "the authored template is the copy's origin")
	assert_ne(copy, _template(), "the copy is not the template")
	assert_eq(copy.caps.size(), 2, "both statuses capped")
	assert_eq(copy.caps.get(_CORRUPTION, -1), _def.intakes[0].innate, "corruption at its innate load")
	assert_eq(copy.caps.get(_CURSE, -1), _def.intakes[1].innate, "curse at its innate load")


func test_the_template_is_never_mutated() -> void:
	Infusion.innate(_def).bag(_def)
	Infusion.for_cast(_def, {&"corruption": 3}).bag(_def)
	assert_true(_template().caps.is_empty(), "template.caps stays empty")


func test_two_distinct_templates_make_two_effects() -> void:
	var a := CleanseEffect.new()
	var b := CleanseEffect.new()
	var bag := LoadBag.new()
	_use_of(a).spend(null, _CORRUPTION, 4, bag)
	_use_of(b).spend(null, _CURSE, 7, bag)
	assert_eq(bag.riders.size(), 2, "one copy per template")
	if bag.riders.size() == 2:
		assert_eq((bag.riders[0] as CleanseEffect).template, a)
		assert_eq((bag.riders[1] as CleanseEffect).template, b)
		assert_eq((bag.riders[0] as CleanseEffect).caps, {_CORRUPTION: 4}, "caps stay per template")
		assert_eq((bag.riders[1] as CleanseEffect).caps, {_CURSE: 7})


func test_a_row_without_a_status_caps_nothing() -> void:
	var bag := LoadBag.new()
	_use_of(CleanseEffect.new()).spend(null, null, 9, bag)
	assert_eq(bag.riders.size(), 0, "no status: no rider")
	CleanseUse.new().spend(null, _CURSE, 9, bag)
	assert_eq(bag.riders.size(), 0, "no effect: no rider")


func test_repeat_spends_on_one_status_accumulate() -> void:
	var tpl := CleanseEffect.new()
	var bag := LoadBag.new()
	_use_of(tpl).spend(null, _CURSE, 4, bag)
	_use_of(tpl).spend(null, _CURSE, 3, bag)
	assert_eq(bag.riders.size(), 1)
	assert_eq((bag.riders[0] as CleanseEffect).caps.get(_CURSE, -1), 7, "loads add")
