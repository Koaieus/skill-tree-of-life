extends GutTest

## Purification: Remedy's kit re-tabled for the Corruption row. Corruption and
## curse cleared one for one, poison not at all. Everything is read off the
## authored `.tres` so a retune moves the expectations with it.

const _DEF_PATH := "res://attack/spell/defs/purification.tres"
const _POISON: StatusDef = preload("res://effects/status/poison.tres")
const _CORRUPTION: StatusDef = preload("res://effects/status/corruption.tres")
const _CURSE: StatusDef = preload("res://effects/status/curse.tres")

var _h: SpellTestHelper
var _def: SpellDef


func before_each() -> void:
	_h = SpellTestHelper.new()
	_def = load(_DEF_PATH) as SpellDef if ResourceLoader.exists(_DEF_PATH) else null


func _cure_effect() -> CureEffect:
	for fx in _def.on_hit_effects:
		if fx is CureEffect:
			return fx
	return null


func _status_filter() -> StatusFilter:
	var f := _def.propagation.filter
	if f is StatusFilter:
		return f
	if f is CompositeFilter:
		for c in (f as CompositeFilter).children:
			if c is StatusFilter:
				return c
	return null


func _rate_of(def: StatusDef) -> float:
	for e in _cure_effect().cure.entries:
		if e.status.id == def.id:
			return e.rate
	return 0.0


## 0 core ─ 1 seed ─┬─ 2 ─┬─ 4      (diamond)
##                  ├─ 3 ─┘
##                  └─ 5 clean ─ 6 stained (never reached)
## Returns [nodes, outcome, seed_dose].
func _cast() -> Array:
	var graph := _h.make_graph([[0, 1], [1, 2], [1, 3], [2, 4], [3, 4], [1, 5], [5, 6]], self)
	var me := _h.make_entity(graph, "A", Color.GREEN)
	_h.give_big_hp(me)
	_h.assign_owner(graph, me, [0, 1, 2, 3, 4, 5, 6])
	_h.set_spell_damage(me, 10.0)
	var n := graph.get_skill_nodes()
	n[1].get_combat().apply_status(_CORRUPTION, 2.0)
	n[1].get_combat().apply_status(_POISON, 4.0)
	n[2].get_combat().apply_status(_CURSE, 1.0)
	n[3].get_combat().apply_status(_CORRUPTION, 1.0)
	n[3].get_combat().apply_status(_CURSE, 2.0)
	n[4].get_combat().apply_status(_CORRUPTION, 50.0)
	n[6].get_combat().apply_status(_CORRUPTION, 50.0)
	var dose := SpellResolver.impact_damage(_def, n[0], me.stat_board)
	var outcome := SpellResolver.resolve(_def, n[1], n[0], me, graph)
	return [n, outcome, dose]


func _cures(outcome: AttackOutcome) -> Array:
	return outcome.hits.filter(func(hit): return hit is CureInstance)


func _cost(ci: CureInstance) -> float:
	var total := 0.0
	for i in ci.defs.size():
		total += ci.cleared[i] / _rate_of(ci.defs[i])
	return total


func test_the_def_exists_and_is_the_catalogs() -> void:
	assert_not_null(_def, "purification.tres is authored")
	if _def == null:
		return
	assert_eq(SpellCatalog.by_id(&"purification"), _def, "registered in SpellCatalog")
	assert_not_null(_cure_effect(), "the dose is a CureEffect")


func test_status_filter_lists_the_cure_tables_statuses() -> void:
	assert_not_null(_def)
	if _def == null:
		return
	var sf := _status_filter()
	var fx := _cure_effect()
	assert_not_null(sf)
	assert_not_null(fx)
	if sf == null or fx == null:
		return
	var table: Array[StatusDef] = []
	for e in fx.cure.entries:
		table.append(e.status)
	assert_eq(sf.statuses, table, "the filter's defs ARE the cure table's defs")
	assert_true(_def.propagation.spread is NeedSplitSpread)
	assert_eq((_def.propagation.spread as NeedSplitSpread).cure, fx.cure)


func test_corruption_and_curse_are_cured_poison_is_not() -> void:
	assert_not_null(_def)
	if _def == null:
		return
	assert_gt(_rate_of(_CORRUPTION), 0.0)
	assert_gt(_rate_of(_CURSE), 0.0)
	assert_eq(_rate_of(_POISON), 0.0, "poison is the owner's 'almost nothing'")
	var r := _cast()
	var n: Array = r[0]
	var seen: Dictionary = {}
	for ci: CureInstance in _cures(r[1]):
		for i in ci.defs.size():
			seen[ci.defs[i].id] = true
			if ci.defs[i].id == _POISON.id:
				assert_eq(ci.cleared[i], 0.0, "poison untouched")
	assert_true(seen.has(_CORRUPTION.id))
	assert_true(seen.has(_CURSE.id))


func test_dose_spent_never_exceeds_seed_and_no_landing_past_clean() -> void:
	assert_not_null(_def)
	if _def == null:
		return
	var r := _cast()
	var n: Array = r[0]
	var dose: float = r[2]
	assert_gt(dose, 0.0)
	var spent := 0.0
	for ci: CureInstance in _cures(r[1]):
		spent += _cost(ci)
	assert_lte(spent, dose + 0.0001, "never more than the seed dose")
	for hit in (r[1] as AttackOutcome).hits:
		assert_false(hit is DamageInstance, "a cure dose is not damage")
		assert_ne(hit.target, n[5], "clean node 5 is not walked")
		assert_ne(hit.target, n[6], "stained node 6 sits past a clean one")
