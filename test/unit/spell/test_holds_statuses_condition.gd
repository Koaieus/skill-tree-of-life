extends GutTest

## [HoldsStatusesCondition] — true iff the landed spot holds EVERY listed
## status, read through [method LandingContext.spot_stacks_of] (node rows plus,
## on a core node, the owner's entity rows).

const _CORRUPTION: StatusDef = preload("res://effects/status/corruption.tres")
const _CURSE: StatusDef = preload("res://effects/status/curse.tres")

var _h: SpellTestHelper
var _graph: Graph
var _owner: Entity
var _n: Array[SkillNode] = []


## 0 owner core ─ 1 owner ─ 2 neutral
func before_each() -> void:
	_h = SpellTestHelper.new()
	_graph = _h.make_graph([[0, 1], [1, 2]], self)
	_owner = _h.make_entity(_graph, "A", Color.GREEN)
	_h.assign_owner(_graph, _owner, [0, 1])
	_n.assign(_graph.get_skill_nodes())


func _cond(defs: Array[StatusDef]) -> HoldsStatusesCondition:
	var c := HoldsStatusesCondition.new()
	c.statuses = defs
	return c


func _lctx(node: SkillNode) -> LandingContext:
	var ctx := PropagationContext.new()
	ctx.graph = _graph
	var p := CastSpell.new()
	p.current_node = node
	p.graph = _graph
	return LandingContext.for_test(p, node, ctx)


func test_an_empty_list_is_never_true() -> void:
	_n[1].get_combat().adjust_status_power(_CORRUPTION, 3.0)
	assert_false(_cond([]).evaluate(_lctx(_n[1])), "empty list")


func test_a_null_entry_is_false() -> void:
	_n[1].get_combat().adjust_status_power(_CORRUPTION, 3.0)
	assert_false(_cond([_CORRUPTION, null]).evaluate(_lctx(_n[1])), "null entry")


func test_a_null_context_or_node_is_false() -> void:
	var cond := _cond([_CORRUPTION])
	assert_false(cond.evaluate(null), "null context")
	assert_false(cond.evaluate(_lctx(null)), "null node")


func test_one_of_two_held_is_false_both_is_true() -> void:
	var cond := _cond([_CORRUPTION, _CURSE])
	var spot := _n[1]
	assert_false(cond.evaluate(_lctx(spot)), "nothing held")
	spot.get_combat().adjust_status_power(_CORRUPTION, 3.0)
	assert_false(cond.evaluate(_lctx(spot)), "corruption alone")
	spot.get_combat().adjust_status_power(_CURSE, 1.0)
	assert_true(cond.evaluate(_lctx(spot)), "both held")


func test_the_other_node_s_stacks_do_not_count() -> void:
	var cond := _cond([_CORRUPTION, _CURSE])
	_n[1].get_combat().adjust_status_power(_CORRUPTION, 3.0)
	_n[2].get_combat().adjust_status_power(_CURSE, 3.0)
	assert_false(cond.evaluate(_lctx(_n[1])), "split across two nodes")
	assert_false(cond.evaluate(_lctx(_n[2])), "split across two nodes")


func test_on_a_core_the_owner_s_entity_row_counts() -> void:
	var cond := _cond([_CORRUPTION, _CURSE])
	var core := _n[0]
	_owner.get_combat().adjust_status_power(_CORRUPTION, 2.0)
	assert_false(cond.evaluate(_lctx(core)), "entity row alone, one status")
	core.get_combat().adjust_status_power(_CURSE, 5.0)
	assert_true(cond.evaluate(_lctx(core)), "entity row + node row")
	_n[1].get_combat().adjust_status_power(_CURSE, 5.0)
	assert_false(cond.evaluate(_lctx(_n[1])), "a non-core node ignores the entity row")


func test_description_names_the_statuses_lowercased() -> void:
	assert_eq(_cond([_CORRUPTION, _CURSE]).get_description(), "on a node holding corruption and curse")
	assert_eq(_cond([]).get_description(), "", "empty list: no description")
