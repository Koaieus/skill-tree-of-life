extends GutTest

## [NeedSplitSpread]: the whole-number leftover dose is apportioned over the
## eligible children by largest remainder, weighted by [method Cure.need_of];
## each pick's share is alloc / leftover, so shares x leftover sum to the
## leftover exactly. A zero-need child, or a zero allocation, gets no pick.

const H := preload("res://test/unit/spell/spell_test_helper.gd")


class FakeCtx extends PropagationContext:
	## node -> { status_id: stacks }
	var stacks: Dictionary = {}

	func stacks_of(node: SkillNode, status_id: StringName) -> float:
		return float(stacks.get(node, {}).get(status_id, 0.0))


var h: SpellTestHelper
var _nodes: Array[SkillNode]
var _ctx: FakeCtx
var _poison: StatusDef
var _rate: float
var _spread: NeedSplitSpread


func before_each() -> void:
	h = H.new()
	var graph := h.make_graph([[0, 1], [0, 2], [0, 3], [0, 4]], self)
	_nodes = graph.get_skill_nodes()
	_ctx = FakeCtx.new()
	_poison = StatusDef.new()
	_poison.id = &"poison"
	var e := CureEntry.new()
	e.status = _poison
	e.rate = 0.5
	_rate = e.rate
	var cure := Cure.new()
	cure.entries = [e] as Array[CureEntry]
	_spread = NeedSplitSpread.new()
	_spread.cure = cure


## Give child i a need of needs[i] (stacks = need x rate).
func _select(leftover: float, needs: Array) -> Array[PropagationPick]:
	var eligible: Array[SkillNode] = []
	for i in needs.size():
		var nb := _nodes[i + 1]
		_ctx.stacks[nb] = {&"poison": float(needs[i]) * _rate}
		eligible.append(nb)
	var p := CastSpell.new()
	p.current_node = _nodes[0]
	p.source = _nodes[0]
	p.damage = leftover
	return _spread.select(eligible, LandingContext.for_test(p, _nodes[0], _ctx))


func _alloc_by_node(picks: Array[PropagationPick], leftover: float) -> Dictionary:
	var out := {}
	for pick in picks:
		out[pick.node] = roundi(pick.share * leftover)
	return out


func _sum_dose(picks: Array[PropagationPick], leftover: float) -> float:
	var s := 0.0
	for pick in picks:
		s += pick.share * leftover
	return s


func test_proportional_needs_apportion_exactly() -> void:
	var picks := _select(7.0, [1, 2, 4])
	assert_eq(picks.size(), 3)
	var alloc := _alloc_by_node(picks, 7.0)
	assert_eq(alloc.get(_nodes[1]), 1)
	assert_eq(alloc.get(_nodes[2]), 2)
	assert_eq(alloc.get(_nodes[3]), 4)
	assert_almost_eq(_sum_dose(picks, 7.0), 7.0, 0.0001, "conserved")


func test_equal_needs_get_whole_shares_summing_to_leftover() -> void:
	var picks := _select(3.0, [1, 1, 1, 1])
	assert_eq(picks.size(), 3, "three whole doses, the fourth child gets none")
	for pick in picks:
		assert_almost_eq(pick.share * 3.0, 1.0, 0.0001, "a whole dose each")
	assert_almost_eq(_sum_dose(picks, 3.0), 3.0, 0.0001, "conserved")


func test_tie_breaks_by_eligible_order() -> void:
	var picks := _select(3.0, [1, 1, 1, 1])
	var got: Array = picks.map(func(p: PropagationPick) -> SkillNode: return p.node)
	assert_eq(got, [_nodes[1], _nodes[2], _nodes[3]], "deterministic across peers")


func test_zero_need_child_gets_no_pick() -> void:
	var picks := _select(5.0, [2, 0, 3])
	var alloc := _alloc_by_node(picks, 5.0)
	assert_false(alloc.has(_nodes[2]), "clean child skipped")
	assert_eq(alloc.get(_nodes[1]), 2)
	assert_eq(alloc.get(_nodes[3]), 3)
	assert_almost_eq(_sum_dose(picks, 5.0), 5.0, 0.0001, "conserved")


func test_uneven_split_conserves_by_largest_remainder() -> void:
	# quotas 5 x {1,1,1}/3 = 1.67 each: floors 1,1,1, the two leftover units go in eligible order
	var picks := _select(5.0, [1, 1, 1])
	var alloc := _alloc_by_node(picks, 5.0)
	assert_eq([alloc.get(_nodes[1]), alloc.get(_nodes[2]), alloc.get(_nodes[3])], [2, 2, 1])
	assert_almost_eq(_sum_dose(picks, 5.0), 5.0, 0.0001, "conserved")


func test_no_leftover_no_picks() -> void:
	assert_eq(_select(0.0, [1, 2]).size(), 0)
	assert_eq(_select(0.9, [1, 2]).size(), 0, "below one whole dose")


func test_all_clean_no_picks() -> void:
	assert_eq(_select(4.0, [0, 0]).size(), 0)
