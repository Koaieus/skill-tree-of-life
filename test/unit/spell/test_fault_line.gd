extends GutTest

## Fault Line's parts: the hop gate on its intake load ([HopIndexCondition]),
## the crack's re-read at each arrival ([StatusShareReseed] on a
## [CarriedScalar]) and the status landing that takes its power from that
## carried value ([member ApplyStatusEffect.power_from]). Ratios and relations
## only — every number is read off the arranged fixture.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const _SUNDER := preload("res://effects/status/sunder.tres")

var _h: SpellTestHelper
var _graph: Graph
var _n: Array[SkillNode]


func before_each() -> void:
	_h = H.new()
	_graph = _h.make_graph([[0, 1], [1, 2]], self)
	var e := _h.make_entity(_graph, "Red", Color.RED)
	_h.assign_owner(_graph, e, [0, 1, 2])
	_n = _graph.get_skill_nodes()


func _lctx(node: SkillNode, hop: int, extras: Array[PayloadState] = []) -> LandingContext:
	var c := PropagationContext.new()
	c.graph = _graph
	c.world = CombatWorld.shadow()
	var p := CastSpell.new()
	p.current_node = node
	p.graph = _graph
	p.hop_index = hop
	p.extras = extras
	return LandingContext.for_test(p, node, c)


func _hop(min_hop: int, max_hop: int) -> HopIndexCondition:
	var c := HopIndexCondition.new()
	c.min_hop = min_hop
	c.max_hop = max_hop
	return c


func _crack(stacks_share: float, min_value: float = -INF) -> CarriedScalar:
	var r := StatusShareReseed.new()
	r.status_id = _SUNDER.id
	r.share = stacks_share
	var s := CarriedScalar.new()
	s.id = &"crack"
	s.reseed = r
	s.min_value = min_value
	return s


# ── HopIndexCondition ──────────────────────────────────────────────────────


func test_max_hop_zero_holds_at_the_seed_only() -> void:
	var c := _hop(0, 0)
	assert_true(c.evaluate(_lctx(_n[1], 0)), "the seed")
	assert_false(c.evaluate(_lctx(_n[1], 1)), "hop 1")
	assert_false(c.evaluate(_lctx(_n[1], 3)), "hop 3")


func test_min_hop_one_unbounded_holds_off_the_seed() -> void:
	var c := _hop(1, -1)
	assert_false(c.evaluate(_lctx(_n[1], 0)), "not the seed")
	assert_true(c.evaluate(_lctx(_n[1], 1)), "hop 1")
	assert_true(c.evaluate(_lctx(_n[1], 7)), "any hop beyond")


func test_a_window_holds_inside_it_only() -> void:
	var c := _hop(1, 2)
	assert_false(c.evaluate(_lctx(_n[1], 0)))
	assert_true(c.evaluate(_lctx(_n[1], 2)))
	assert_false(c.evaluate(_lctx(_n[1], 3)))


# ── StatusShareReseed on a CarriedScalar ───────────────────────────────────


func test_the_reseed_reads_the_landed_stacks_not_the_carried_value() -> void:
	var stacks := 6.0
	_n[1].get_combat().apply_status(_SUNDER, stacks)
	var reseed := _crack(0.5).reseed
	var lctx := _lctx(_n[1], 1)
	assert_almost_eq(reseed.reseed(999.0, lctx, null), 0.5 * stacks, 0.001,
			"share × what is there now; the incoming value is ignored")
	assert_almost_eq(reseed.reseed(0.0, _lctx(_n[2], 1), null), 0.0, 0.001,
			"a clean node carries nothing")


func test_more_stacks_on_the_node_carry_a_bigger_crack() -> void:
	_n[1].get_combat().apply_status(_SUNDER, 4.0)
	_n[2].get_combat().apply_status(_SUNDER, 10.0)
	var crack := _crack(0.5)
	var pick := PropagationPick.new()
	var parent := crack.seed(null)
	var thin := crack.mint(parent, pick, _lctx(_n[1], 0), 0) as CarriedScalar.State
	var thick := crack.mint(parent, pick, _lctx(_n[2], 0), 0) as CarriedScalar.State
	assert_gt(thick.value, thin.value, "the re-read follows the node's stacks")


func test_a_crack_thinner_than_min_value_is_terminal() -> void:
	_n[1].get_combat().apply_status(_SUNDER, 1.0)
	_n[2].get_combat().apply_status(_SUNDER, 4.0)
	var crack := _crack(0.5, 1.0)
	var parent := crack.seed(null)
	var pick := PropagationPick.new()
	assert_true(crack.mint(parent, pick, _lctx(_n[1], 0), 0).terminal, "one stack halves below 1: the walk ends")
	assert_false(crack.mint(parent, pick, _lctx(_n[2], 0), 0).terminal, "four stacks carry on")


# ── ApplyStatusEffect.power_from ───────────────────────────────────────────


func _emitted_power(effect: ApplyStatusEffect, lctx: HitLanding) -> float:
	var before := lctx.hits.size()
	effect.apply(lctx)
	assert_eq(lctx.hits.size(), before + 1, "one status emitted")
	return (lctx.hits[lctx.hits.size() - 1] as StatusInstance).power


func _state(id: StringName, value: float) -> CarriedScalar.State:
	var tmpl := CarriedScalar.new()
	tmpl.id = id
	var st := CarriedScalar.State.new()
	st.template = tmpl
	st.value = value
	return st


func test_power_from_takes_the_carried_value() -> void:
	var fx := ApplyStatusEffect.new()
	fx.def = _SUNDER
	fx.power = 1.0
	fx.power_from = &"crack"
	var carried := 7.0
	var lctx := _lctx(_n[1], 1, [_state(&"crack", carried)] as Array[PayloadState])
	assert_almost_eq(_emitted_power(fx, lctx), carried, 0.001, "the carried value, not the authored power")


func test_power_from_falls_back_to_power_without_the_extension() -> void:
	var fx := ApplyStatusEffect.new()
	fx.def = _SUNDER
	fx.power = 3.0
	fx.power_from = &"crack"
	var lctx := _lctx(_n[1], 1, [_state(&"other", 9.0)] as Array[PayloadState])
	assert_almost_eq(_emitted_power(fx, lctx), fx.power, 0.001, "no crack on the payload")


func test_empty_power_from_ignores_a_carried_scalar() -> void:
	var fx := ApplyStatusEffect.new()
	fx.def = _SUNDER
	fx.power = 3.0
	var lctx := _lctx(_n[1], 1, [_state(&"crack", 9.0)] as Array[PayloadState])
	assert_almost_eq(_emitted_power(fx, lctx), fx.power, 0.001, "today's behaviour")
