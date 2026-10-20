extends GutTest

## Remedy: the Poison row's boon face. No damage — the hit is a cure dose that
## drains in place, its leftover split by need over infected friendly
## neighbours, converging doses summed. Everything is read off the authored
## `.tres` so a retune moves the expectations with it.

const _DEF_PATH := "res://attack/spell/defs/remedy.tres"
const _POISON: StatusDef = preload("res://effects/status/poison.tres")
const _BLEEDING: StatusDef = preload("res://effects/status/bleeding.tres")
const _CORRUPTION: StatusDef = preload("res://effects/status/corruption.tres")

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


## 0 core ─ 1 seed ─┬─ 2 ─┬─ 4      (diamond: 2 and 3 both feed 4)
##                  ├─ 3 ─┘
##                  └─ 5 clean ─ 6 infected (never reached)
## Returns [nodes, outcome, seed_dose].
func _cast() -> Array:
	var graph := _h.make_graph([[0, 1], [1, 2], [1, 3], [2, 4], [3, 4], [1, 5], [5, 6]], self)
	var me := _h.make_entity(graph, "A", Color.GREEN)
	_h.give_big_hp(me)
	_h.assign_owner(graph, me, [0, 1, 2, 3, 4, 5, 6])
	_h.set_spell_damage(me, 10.0)
	var n := graph.get_skill_nodes()
	n[1].get_combat().apply_status(_POISON, 2.0)
	n[2].get_combat().apply_status(_POISON, 1.0)
	n[3].get_combat().apply_status(_POISON, 1.0)
	n[3].get_combat().apply_status(_BLEEDING, 2.0)
	n[3].get_combat().apply_status(_CORRUPTION, 5.0)
	n[4].get_combat().apply_status(_POISON, 50.0)
	n[6].get_combat().apply_status(_POISON, 50.0)
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
	assert_not_null(_def, "remedy.tres is authored")
	if _def == null:
		return
	assert_eq(SpellCatalog.by_id(&"remedy"), _def, "registered in SpellCatalog")
	assert_not_null(_cure_effect(), "the dose is a CureEffect")


## (e) the propagation reaches exactly the nodes the dose can cure.
func test_status_filter_lists_the_cure_tables_statuses() -> void:
	assert_not_null(_def)
	if _def == null:
		return
	var sf := _status_filter()
	var fx := _cure_effect()
	assert_not_null(sf, "propagation is gated on infection")
	assert_not_null(fx)
	if sf == null or fx == null:
		return
	var table: Array[StatusDef] = []
	for e in fx.cure.entries:
		table.append(e.status)
	assert_eq(sf.statuses, table, "the filter's defs ARE the cure table's defs")
	assert_true(_def.propagation.spread is NeedSplitSpread)
	assert_eq((_def.propagation.spread as NeedSplitSpread).cure, fx.cure,
			"one Cure resource shared by the effect and the split")
	assert_true(_def.propagation.reducer is SumDamageReducer, "converging doses add")


## No damage, ever: the dose never lands as a DamageInstance.
func test_remedy_deals_no_damage() -> void:
	assert_not_null(_def)
	if _def == null:
		return
	var r := _cast()
	for hit in (r[1] as AttackOutcome).hits:
		assert_false(hit is DamageInstance, "a cure dose is not damage: %s" % hit)


## (a) the walk spends no more than the seed dose, and with every branch
## still infected it spends it all — the fork's two leftovers summed at 4.
func test_dose_is_conserved_across_the_fork() -> void:
	assert_not_null(_def)
	if _def == null:
		return
	var r := _cast()
	var n: Array = r[0]
	var dose: float = r[2]
	assert_gt(dose, 0.0)
	var spent := 0.0
	var landed: Dictionary = {}
	for ci: CureInstance in _cures(r[1]):
		spent += _cost(ci)
		landed[ci.target] = true
	assert_true(landed.has(n[4]), "the converged node is reached")
	assert_lte(spent, dose + 0.0001, "never more than the seed dose")
	assert_almost_eq(spent, dose, 0.0001, "the leftover is conserved through the fork")


## (b) a clean node stops the walk — nothing lands on it or past it.
func test_no_landing_past_a_clean_node() -> void:
	assert_not_null(_def)
	if _def == null:
		return
	var r := _cast()
	var n: Array = r[0]
	for hit in (r[1] as AttackOutcome).hits:
		assert_ne(hit.target, n[5], "clean node 5 is not walked")
		assert_ne(hit.target, n[6], "infected node 6 sits past a clean one")


## (c) heal per landing = Σcleared × the heal term's per_stack.
func test_heal_is_cleared_times_heal_per_stack() -> void:
	assert_not_null(_def)
	if _def == null:
		return
	var r := _cast()
	var hps := (_cure_effect().terms[0] as HealPerStackTerm).per_stack
	var cures := _cures(r[1])
	assert_gt(cures.size(), 0)
	for ci: CureInstance in cures:
		var cleared := 0.0
		for c in ci.cleared:
			cleared += c
		assert_almost_eq(ci.heal, cleared * hps, 0.0001)


## (d) corruption is not a sickness Remedy treats.
func test_corruption_is_untouched() -> void:
	assert_not_null(_def)
	if _def == null:
		return
	var r := _cast()
	var n: Array = r[0]
	var hit_three := false
	for ci: CureInstance in _cures(r[1]):
		assert_false(ci.defs.has(_CORRUPTION), "corruption never cleared")
		for d in ci.defs:
			assert_ne(d.id, _CORRUPTION.id)
		if ci.target == n[3]:
			hit_three = true
			assert_true(ci.defs.has(_BLEEDING), "mixed stacks: bleeding cleared at its own rate")
	assert_true(hit_three, "the corrupted node was landed on for its other stacks")
