extends GutTest

## [FoldReducer] owns the merge-then-fold template: [method IncidentReducer._merge_payload_defaults]
## first (MAX hops, visited union), then [code]damage[/code] from the subclass's
## [method FoldReducer._fold_damage]. The four pure folds are its subclasses;
## [CancelIfMultiReducer] is the guard over [FirstReducer].

const SENTINEL := 42.0

var h: SpellTestHelper


## A fold whose damage is a sentinel, recording what it was handed.
class _RecordingFold extends FoldReducer:
	var seen: int = -1

	func _fold_damage(incidents: Array[CastSpell]) -> float:
		seen = incidents.size()
		return SENTINEL


func before_each() -> void:
	h = SpellTestHelper.new()


func _incident(damage: float, hops: float, visited: Array[SkillNode]) -> CastSpell:
	var c := CastSpell.new()
	c.damage = damage
	c.hops_remaining = hops
	c.visited = visited
	return c


func test_the_four_pure_folds_are_fold_reducers() -> void:
	var folds: Array[IncidentReducer] = [
		FirstReducer.new(), MaxDamageReducer.new(),
		SumDamageReducer.new(), CancelIfMultiReducer.new(),
	]
	for r in folds:
		assert_true(r is FoldReducer, "%s is a FoldReducer" % r.get_script().get_global_name())


func test_reduce_merges_metadata_then_sets_damage_from_the_fold() -> void:
	var graph := h.make_graph([[0, 1], [1, 2]], self)
	var n := graph.get_skill_nodes()
	var a: Array[SkillNode] = [n[0], n[1]]
	var b: Array[SkillNode] = [n[1], n[2]]
	var incidents: Array[CastSpell] = [_incident(3.0, 2.0, a), _incident(9.0, 5.0, b)]
	var fold := _RecordingFold.new()
	var merged := fold.reduce(incidents, null)
	assert_not_null(merged, "the template returns a merged payload")
	if merged == null:
		return
	assert_eq(fold.seen, 2, "the fold is handed every incident")
	assert_almost_eq(merged.damage, SENTINEL, 0.0001, "damage comes from _fold_damage")
	assert_almost_eq(merged.hops_remaining, 5.0, 0.0001, "hops_remaining is the MAX")
	assert_eq(merged.visited.size(), 3, "visited is the union")
	for node in n:
		assert_has(merged.visited, node)


func test_cancel_if_multi_fizzles_on_two_and_is_first_wins_on_one() -> void:
	var r := CancelIfMultiReducer.new()
	var none: Array[SkillNode] = []
	var two: Array[CastSpell] = [_incident(3.0, 1.0, none), _incident(9.0, 1.0, none)]
	assert_null(r.reduce(two, null), "two incidents cancel")
	var one: Array[CastSpell] = [_incident(7.0, 1.0, none)]
	var merged := r.reduce(one, null)
	assert_not_null(merged, "one incident lands")
	if merged == null:
		return
	assert_almost_eq(merged.damage, 7.0, 0.0001, "first-wins payload")
