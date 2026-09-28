extends GutTest

## Parent stats (ADR 0029 decision 1 + ADR 0030): a child folds its ancestors'
## BINS (never their base) into its own pipeline, and a parent's move dirties
## its children through the board-wired link. Throwaway defs arrive through
## the [code]StatRegistry.register_def[/code] test seam.

const GP := &"_tp_grand"
const P := &"_tp_parent"
const C := &"_tp_child"
const P2 := &"_tp_parent_two"
const GC := &"_tp_grandchild"

var _registered: Array[StringName] = []


func _def(id: StringName, base: float, parents: Array[StringName] = []) -> StatDef:
	var d := StatDef.new()
	d.id = id
	d.value_type = StatDef.ValueType.FLOAT
	d.default_value = base
	d.parent_ids = parents
	StatRegistry.register_def(d)
	_registered.append(id)
	return d


func after_each() -> void:
	for id in _registered:
		StatRegistry.unregister_def(id)
	_registered.clear()


func _mod(stat_id: StringName, op: StatModifier.Operation, value: float, priority: int = 0) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = op
	m.value = value
	m.priority = priority
	return m


func _pair(parent_base: float = 0.0, child_base: float = 10.0) -> StatBoard:
	_def(P, parent_base)
	_def(C, child_base, [P])
	var b := StatBoard.new()
	b._ensure_stat(P)
	b._ensure_stat(C)
	return b


func test_increases_sum_across_parent_and_child() -> void:
	var b := _pair()
	b.add_modifier(_mod(P, StatModifier.Operation.INCREASE, 20.0))
	b.add_modifier(_mod(C, StatModifier.Operation.INCREASE, 10.0))
	assert_almost_eq(float(b.get_value(C)), 13.0, 0.0001, "one increase sum: 10 x 1.3, not 10 x 1.2 x 1.1")


func test_parent_base_never_enters_child() -> void:
	var b := _pair(99.0, 1.0)
	assert_almost_eq(float(b.get_value(C)), 1.0, 0.0001)
	assert_almost_eq(float(b.get_value(P)), 99.0, 0.0001)


func test_child_minted_before_parent_still_links() -> void:
	_def(P, 0.0)
	_def(C, 10.0, [P])
	var b := StatBoard.new()
	b._ensure_stat(C)
	b._ensure_stat(P)
	b.add_modifier(_mod(P, StatModifier.Operation.ADD_BASE, 5.0))
	assert_almost_eq(float(b.get_value(C)), 15.0, 0.0001, "a descendant present before its parent links when the parent arrives")


func test_grandparent_reaches_grandchild_once() -> void:
	_def(GP, 0.0)
	_def(P, 0.0, [GP])
	_def(P2, 0.0, [GP])
	_def(GC, 10.0, [P, P2])
	var b := StatBoard.new()
	for id in [GP, P, P2, GC]:
		b._ensure_stat(id)
	b.add_modifier(_mod(GP, StatModifier.Operation.ADD_BASE, 1.0))
	assert_almost_eq(float(b.get_value(GC)), 11.0, 0.0001, "two paths, one ancestor: counted once")
	assert_eq(StatRegistry.ancestors_of(GC), [P, P2, GP] as Array[StringName], "nearest-first, deduped")


func test_memo_invalidates_through_parent() -> void:
	var b := _pair()
	assert_almost_eq(float(b.get_value(C)), 10.0, 0.0001)
	b.add_modifier(_mod(P, StatModifier.Operation.ADD_BASE, 2.0))
	assert_almost_eq(float(b.get_value(C)), 12.0, 0.0001, "warm child memo must see a parent move")


func test_memo_invalidates_mid_batch() -> void:
	var b := _pair()
	assert_almost_eq(float(b.get_value(C)), 10.0, 0.0001)
	b.begin_batch()
	b.add_modifier(_mod(P, StatModifier.Operation.ADD_BASE, 3.0))
	assert_almost_eq(float(b.get_value(C)), 13.0, 0.0001, "batching defers notification, never value")
	b.end_batch()


func test_one_child_emission_per_settle_parent_first() -> void:
	var b := _pair()
	var order: Array = []
	b.get_stat(P).value_changed.connect(func() -> void: order.append(P))
	b.get_stat(C).value_changed.connect(func() -> void: order.append(C))
	b.begin_batch()
	b.add_modifier(_mod(C, StatModifier.Operation.ADD_BASE, 1.0))
	b.add_modifier(_mod(P, StatModifier.Operation.ADD_BASE, 1.0))
	b.add_modifier(_mod(P, StatModifier.Operation.ADD_BASE, 1.0))
	assert_eq(order.size(), 0)
	b.end_batch()
	assert_eq(order, [P, C], "one emission each, parent first")


func test_unbatched_parent_move_notifies_child_once() -> void:
	var b := _pair()
	var seen: Array = []
	b.get_stat(C).value_changed.connect(func() -> void: seen.append(1))
	b.add_modifier(_mod(P, StatModifier.Operation.ADD_BASE, 1.0))
	assert_eq(seen.size(), 1)


func test_child_set_beats_parent_set_at_equal_priority() -> void:
	var b := _pair()
	b.add_modifier(_mod(P, StatModifier.Operation.SET, 5.0))
	assert_almost_eq(float(b.get_value(C)), 5.0, 0.0001, "parent SET alone reaches the child")
	b.add_modifier(_mod(C, StatModifier.Operation.SET, 7.0))
	assert_almost_eq(float(b.get_value(C)), 7.0, 0.0001, "the child's own SET is the last source")


func test_every_door_folds_parents() -> void:
	var b := _pair()
	b.add_modifier(_mod(P, StatModifier.Operation.ADD_BASE, 4.0))
	var s := b.get_stat(C)
	var empty: Array[ModifierBins] = []
	assert_almost_eq(float(s.get_value_with(empty)), 14.0, 0.0001)
	assert_almost_eq(s.resolve_with(empty).add, 4.0, 0.0001)


func test_clone_live_relinks_on_the_clone() -> void:
	var b := _pair()
	var c := b.clone_live()
	c.add_modifier(_mod(P, StatModifier.Operation.ADD_BASE, 6.0))
	assert_almost_eq(float(c.get_value(C)), 16.0, 0.0001, "the clone's child follows the clone's parent")
	assert_almost_eq(float(b.get_value(C)), 10.0, 0.0001, "the original's child does not")
	c.release()


func test_registry_drops_a_cycle() -> void:
	var a := _def(&"_tp_a", 0.0)
	_def(&"_tp_b", 0.0, [&"_tp_a"])
	a.parent_ids = [&"_tp_b"]
	StatRegistry.register_def(a)
	assert_push_error("cycle")
	var a_anc := StatRegistry.ancestors_of(&"_tp_a")
	var b_anc := StatRegistry.ancestors_of(&"_tp_b")
	assert_false(a_anc.has(&"_tp_a") or b_anc.has(&"_tp_b"), "no stat is its own ancestor")
	assert_eq(a_anc.size() + b_anc.size(), 1, "exactly one edge of the cycle survives")


func test_registry_drops_an_unknown_parent() -> void:
	_def(C, 0.0, [&"_tp_nobody"])
	assert_push_error("unknown")
	assert_eq(StatRegistry.ancestors_of(C), [] as Array[StringName])
	assert_true(StatRegistry.children_of(&"_tp_nobody").is_empty())


func test_registry_children_and_is_parent() -> void:
	_def(P, 0.0)
	_def(C, 0.0, [P])
	assert_eq(StatRegistry.children_of(P), [C] as Array[StringName])
	assert_true(StatRegistry.is_parent(P))
	assert_false(StatRegistry.is_parent(C))
