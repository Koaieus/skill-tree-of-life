extends GutTest

## [CureEffect]: the hit is the dose, [method Cure.plan] prices it, the
## leftover is written back into [member CastSpell.damage] IN PLACE (the next
## hop inherits it) and one [CureInstance] carries the exact counts. Stacks
## come from a fake context, the world-aware seam the effect reads through.

const H := preload("res://test/unit/spell/spell_test_helper.gd")


class FakeCtx extends PropagationContext:
	## node -> { status_id: stacks }
	var stacks: Dictionary = {}

	func stacks_of(node: SkillNode, status_id: StringName) -> float:
		return float(stacks.get(node, {}).get(status_id, 0.0))


var h: SpellTestHelper
var _graph: Graph
var _node: SkillNode
var _ctx: FakeCtx
var _poison: StatusDef
var _bleed: StatusDef


func before_each() -> void:
	h = H.new()
	_graph = h.make_graph([[0, 1]], self)
	_node = _graph.get_skill_nodes()[0]
	_ctx = FakeCtx.new()
	_poison = _def(&"poison", "Poison")
	_bleed = _def(&"bleeding", "Bleeding")


func _def(id: StringName, display: String) -> StatusDef:
	var d := StatusDef.new()
	d.id = id
	d.display_name = display
	return d


func _entry(def: StatusDef, rate: float) -> CureEntry:
	var e := CureEntry.new()
	e.status = def
	e.rate = rate
	return e


func _effect(rows: Array[CureEntry], heal_per_stack: float = 1.0) -> CureEffect:
	var c := Cure.new()
	c.entries = rows
	var e := CureEffect.new()
	e.cure = c
	var term := HealPerStackTerm.new()
	term.per_stack = heal_per_stack
	e.terms.assign([term])
	return e


## Lands [param dose] on [member _node]; returns the landing context.
func _land(effect: CureEffect, dose: float) -> LandingContext:
	var p := CastSpell.new()
	p.damage = dose
	p.current_node = _node
	p.graph = _graph
	var lctx := LandingContext.for_test(p, _node, _ctx)
	effect.apply(lctx)
	return lctx


func _cures(lctx: LandingContext) -> Array:
	return lctx.cast.outcome.hits.filter(func(hit): return hit is CureInstance)


# ── acceptance 1: drain ────────────────────────────────────────────────────


func test_drain_clears_what_it_can_and_passes_the_rest_on() -> void:
	_ctx.stacks[_node] = {&"poison": 2.0}
	var lctx := _land(_effect([_entry(_poison, 1.0)]), 5.0)
	assert_almost_eq(lctx.payload.damage, 3.0, 0.0001, "5 dose, 2 stacks at 1.0: 3 flow on")
	var cures := _cures(lctx)
	assert_eq(cures.size(), 1, "one CureInstance per landing")
	if cures.size() != 1:
		return
	var ci: CureInstance = cures[0]
	assert_eq(ci.defs, [_poison] as Array[StatusDef])
	assert_eq(Array(ci.cleared), [2.0])
	assert_eq(ci.target, _node)


func test_heal_is_linear_in_stacks_cleared() -> void:
	_ctx.stacks[_node] = {&"poison": 2.0, &"bleeding": 4.0}
	var lctx := _land(_effect([_entry(_poison, 1.0), _entry(_bleed, 1.0)], 1.5), 10.0)
	var ci: CureInstance = _cures(lctx)[0]
	assert_almost_eq(ci.heal, 6.0 * 1.5, 0.0001, "Σcleared × per_stack")
	assert_almost_eq(lctx.payload.damage, 4.0, 0.0001)


# ── acceptance 2: pricing ──────────────────────────────────────────────────


func test_pricing_clears_in_table_order_at_each_rate() -> void:
	var poison := _entry(_poison, 1.0)
	var bleed := _entry(_bleed, 0.5)
	_ctx.stacks[_node] = {&"poison": 1.0, &"bleeding": 4.0}
	var lctx := _land(_effect([poison, bleed]), 3.0)
	var ci: CureInstance = _cures(lctx)[0]
	var bleed_cleared := floorf((3.0 - 1.0 / poison.rate) * bleed.rate)
	assert_eq(ci.defs, [_poison, _bleed] as Array[StatusDef], "table order")
	assert_eq(Array(ci.cleared), [1.0, bleed_cleared], "1 poison, floor(2 × rate) bleeding")
	var left := 3.0 - 1.0 / poison.rate - bleed_cleared / bleed.rate
	assert_almost_eq(lctx.payload.damage, left, 0.0001, "the dose is spent exactly")
	assert_almost_eq(lctx.payload.damage, 0.0, 0.0001)


func test_a_dose_below_one_stacks_price_cures_nothing_and_flows_on_whole() -> void:
	var bleed := _entry(_bleed, 0.5)
	_ctx.stacks[_node] = {&"bleeding": 4.0}
	var dose := 0.5 / bleed.rate  # one dose at rate 0.5 buys half a stack
	var lctx := _land(_effect([bleed]), dose)
	assert_eq(_cures(lctx).size(), 0, "nothing cleared emits nothing")
	assert_almost_eq(lctx.payload.damage, dose, 0.0001, "untouched")


func test_a_clean_node_emits_nothing_and_keeps_the_dose() -> void:
	var lctx := _land(_effect([_entry(_poison, 1.0)]), 5.0)
	assert_eq(lctx.cast.outcome.hits.size(), 0)
	assert_almost_eq(lctx.payload.damage, 5.0, 0.0001)


func test_no_cure_table_is_inert() -> void:
	_ctx.stacks[_node] = {&"poison": 2.0}
	var e := CureEffect.new()
	var lctx := _land(e, 5.0)
	assert_eq(lctx.cast.outcome.hits.size(), 0)
	assert_almost_eq(lctx.payload.damage, 5.0, 0.0001)


# ── description ────────────────────────────────────────────────────────────


func test_description_names_the_statuses_and_the_dose() -> void:
	var d := _effect([_entry(_poison, 1.0), _entry(_bleed, 0.5)]).get_description()
	assert_string_contains(d, "Cures")
	assert_string_contains(d, "Poison")
	assert_string_contains(d, "Bleeding")
	assert_string_contains(d, "(dose = hit)")
	assert_ne(CureEffect.new().get_description(), "", "a bare effect still has a line")
