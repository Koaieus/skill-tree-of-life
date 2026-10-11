extends GutTest

## [Cure]'s pricing math: one dose, each entry priced by its `rate`
## (stacks per dose), cleared in table order; `need_of` is the dose that
## cures a node fully. Stacks come from a fake context, the seam `Cure`
## reads through, so this pins the formula alone.

const H := preload("res://test/unit/spell/spell_test_helper.gd")


class FakeCtx extends PropagationContext:
	## node -> { status_id: stacks }
	var stacks: Dictionary = {}

	func stacks_of(node: SkillNode, status_id: StringName) -> float:
		return float(stacks.get(node, {}).get(status_id, 0.0))


var h: SpellTestHelper
var _node: SkillNode
var _ctx: FakeCtx
var _lctx: LandingContext
var _poison: StatusDef
var _bleed: StatusDef


func before_each() -> void:
	h = H.new()
	var graph := h.make_graph([[0, 1]], self)
	_node = graph.get_skill_nodes()[0]
	_ctx = FakeCtx.new()
	_lctx = LandingContext.for_test(null, _node, _ctx)
	_poison = _def(&"poison")
	_bleed = _def(&"bleeding")


func _def(id: StringName) -> StatusDef:
	var d := StatusDef.new()
	d.id = id
	return d


func _entry(def: StatusDef, rate: float) -> CureEntry:
	var e := CureEntry.new()
	e.status = def
	e.rate = rate
	return e


func _cure(rows: Array[CureEntry]) -> Cure:
	var c := Cure.new()
	c.entries = rows
	return c


func _stack(stacks: Dictionary) -> void:
	_ctx.stacks[_node] = stacks


func test_drain_clears_what_it_can_and_spends_only_that() -> void:
	var p := _entry(_poison, 1.0)
	var cure := _cure([p] as Array[CureEntry])
	_stack({&"poison": 2.0})
	var plan := cure.plan(_node, 5.0, _lctx)
	assert_eq(plan.get("cleared", {}).get(_poison, 0.0), 2.0, "2 stacks cleared")
	assert_almost_eq(float(plan.get("spent", -1.0)), 2.0 / p.rate, 0.0001, "spent = cleared / rate")
	assert_almost_eq(5.0 - float(plan.get("spent", -1.0)), 3.0, 0.0001, "3 flow on")


func test_pricing_clears_in_table_order_at_each_rate() -> void:
	var p := _entry(_poison, 1.0)
	var b := _entry(_bleed, 0.5)
	var cure := _cure([p, b] as Array[CureEntry])
	_stack({&"poison": 1.0, &"bleeding": 4.0})
	var dose := 3.0
	var plan := cure.plan(_node, dose, _lctx)
	var want_p: float = min(1.0, floor(dose * p.rate))
	var left := dose - want_p / p.rate
	var want_b: float = min(4.0, floor(left * b.rate))
	assert_eq(plan.cleared.get(_poison, 0.0), want_p, "poison first, at its rate")
	assert_eq(plan.cleared.get(_bleed, 0.0), want_b, "bleeding takes floor(left x rate)")
	assert_almost_eq(dose - float(plan.spent), left - want_b / b.rate, 0.0001, "spent = sum cleared / rate")
	assert_almost_eq(dose - float(plan.spent), 0.0, 0.0001, "the spec's case drains to 0")


func test_a_dose_below_one_stacks_price_cures_nothing() -> void:
	var b := _entry(_bleed, 0.5)
	var cure := _cure([b] as Array[CureEntry])
	_stack({&"bleeding": 4.0})
	var dose := 1.0  # at rate 0.5: floor(0.5) = 0
	var plan := cure.plan(_node, dose, _lctx)
	assert_false(plan.get("cleared", {_bleed: 1.0}).has(_bleed), "no entry for a zero clear")
	assert_almost_eq(float(plan.get("spent", -1.0)), 0.0, 0.0001, "nothing spent")


func test_cleared_omits_zero_rows_and_keeps_table_order() -> void:
	var p := _entry(_poison, 1.0)
	var b := _entry(_bleed, 0.5)
	var cure := _cure([b, p] as Array[CureEntry])
	_stack({&"poison": 3.0, &"bleeding": 2.0})
	var plan := cure.plan(_node, 10.0, _lctx)
	assert_eq(plan.cleared.keys(), [_bleed, _poison], "table order")
	_stack({&"poison": 3.0})
	plan = cure.plan(_node, 10.0, _lctx)
	assert_eq(plan.cleared.keys(), [_poison], "a clean status has no row")


func test_need_is_sum_of_stacks_over_rate() -> void:
	var p := _entry(_poison, 1.0)
	var b := _entry(_bleed, 0.5)
	var cure := _cure([p, b] as Array[CureEntry])
	_stack({&"poison": 3.0, &"bleeding": 4.0})
	assert_almost_eq(cure.need_of(_node, _lctx), 3.0 / p.rate + 4.0 / b.rate, 0.0001)
	_stack({})
	assert_almost_eq(cure.need_of(_node, _lctx), 0.0, 0.0001, "a clean node needs nothing")


func test_need_is_exactly_the_dose_that_cures_fully() -> void:
	var p := _entry(_poison, 1.0)
	var b := _entry(_bleed, 0.5)
	var cure := _cure([p, b] as Array[CureEntry])
	_stack({&"poison": 3.0, &"bleeding": 4.0})
	var need := cure.need_of(_node, _lctx)
	var plan := cure.plan(_node, need, _lctx)
	assert_eq(plan.cleared.get(_poison, 0.0), 3.0)
	assert_eq(plan.cleared.get(_bleed, 0.0), 4.0)
	assert_almost_eq(float(plan.spent), need, 0.0001)
