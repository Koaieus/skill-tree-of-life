extends GutTest

## `DistanceScale.NOT_GRANTED` (NaN) is the scale's way to say "no modifier
## here" that is not a number — distinct from a real `+0`, which under
## `discard = NONE` is a ledger row. The aura drops a NaN leaf before the
## discard policy ever sees it. Also pins the per-frame evaluation memo: one
## `scale_at` per distinct input tuple per recompute.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem


## Counts `scale_at` calls — a spy on the scale's own door, not a reach-in.
class CountingScale:
	extends ExpressionScale
	var calls: int = 0

	func scale_at(distance: float, max_distance: float, value: float,
			hops: float, euclid: float, relation: int) -> float:
		calls += 1
		return super.scale_at(distance, max_distance, value, hops, euclid, relation)


func before_each() -> void:
	AuraDistanceCache.clear()
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)


func _node(n: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = n
	sn.position = pos
	_graph.add_skill_node(sn)
	return sn


## One straight line N0—N1—…—N(count-1); hop distance from N0 IS the index.
func _chain(count: int) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	for i in count:
		out.append(_node("N%d" % i, Vector2(i * 100.0, 0.0)))
	for i in count - 1:
		_graph.add_edge(out[i], out[i + 1])
	return out


## A hub with [param leaves] spokes: every leaf is exactly one hop out.
func _star(leaves: int) -> Array[SkillNode]:
	var out: Array[SkillNode] = [_node("Hub", Vector2.ZERO)]
	for i in leaves:
		var a := TAU * i / leaves
		out.append(_node("L%d" % i, Vector2(100.0, 0.0).rotated(a)))
		_graph.add_edge(out[0], out[i + 1])
	return out


func _spawn_owning(core: SkillNode, owned: Array[SkillNode]) -> Entity:
	var ent := autofree(Entity.new()) as Entity
	ent.display_name = "E"
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	# entities_container: NodeEffectReadout.gather walks it for grant rows.
	_graph.entities_container.add_child(ent)
	await get_tree().process_frame
	for n in owned:
		_alloc.force_allocate(ent, n)
	ent.core_location = core
	ent.stat_board.armor.base_value = 0.0
	return ent


func _armor_mod(value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = &"armor"
	m.operation = StatModifier.Operation.ADD_BONUS
	m.value = value
	return m


func _armor(n: SkillNode) -> float:
	return float(n.get_local_value(&"armor"))


func _aura(scale: ExpressionScale, hops: int, mods: Array[StatModifier],
		discard: int = AuraEffect.Discard.NON_POSITIVE) -> AuraEffect:
	var aura := AuraEffect.new()
	var reach := HopRangeFinder.new()
	reach.max_hops = hops
	aura.reach = reach
	aura.distance_scale = scale
	aura.discard = discard
	aura.modifiers = mods
	return aura


func _expr(formula: String) -> ExpressionScale:
	var s := ExpressionScale.new()
	s.formula = formula
	return s


## How many modifier rows any aura has put on this node — the only way to tell
## "granted 0" from "not granted".
func _grant_rows(n: SkillNode) -> int:
	return NodeEffectReadout.gather(n, _graph).size()


func test_not_granted_is_nan() -> void:
	assert_true(is_nan(DistanceScale.NOT_GRANTED), "the sentinel is NaN, tested with is_nan never ==")


## `[NAN, v][int(h >= 2)]` — Expression has no ternary; an array literal
## indexed by the bool-as-int selects. Under `discard = NONE` the NaN branch
## grants NOTHING (no ledger row) while the `0.0` branch grants a real +0.
func test_nan_branch_grants_nothing_where_zero_branch_grants_a_row() -> void:
	var chain := _chain(5)
	var ent: Entity = await _spawn_owning(chain[0], chain)
	var inst := ent.grant_effect(_aura(_expr("[NAN, v][int(h >= 2)]"), 3, [_armor_mod(5.0)], AuraEffect.Discard.NONE))
	assert_eq(_grant_rows(chain[1]), 0, "h = 1: NOT_GRANTED leaves no ledger row")
	assert_eq(_grant_rows(chain[2]), 1, "h = 2: granted")
	assert_almost_eq(_armor(chain[2]), 5.0, 0.001, "h = 2: v lands")
	ent.revoke_effect(inst)

	ent.grant_effect(_aura(_expr("[0.0, v][int(h >= 2)]"), 3, [_armor_mod(5.0)], AuraEffect.Discard.NONE))
	assert_eq(_grant_rows(chain[1]), 1, "h = 1: a literal 0 under discard NONE is a real +0 row")
	assert_almost_eq(_armor(chain[1]), 0.0, 0.001, "h = 1: +0")
	assert_eq(_grant_rows(chain[2]), 1, "h = 2: granted")


## `v * d / d` is `0.0 / 0.0` = NaN at the source. Before the NaN door every
## discard mode kept it (no comparison against NaN is true) and a NaN modifier
## landed on the core; now the source is simply not granted.
func test_a_formula_that_is_nan_at_the_source_grants_nothing_there() -> void:
	var chain := _chain(3)
	var ent: Entity = await _spawn_owning(chain[0], chain)
	ent.grant_effect(_aura(_expr("v * d / d"), 2, [_armor_mod(5.0)]))
	assert_eq(_grant_rows(chain[0]), 0, "d = 0: NaN → not granted")
	assert_almost_eq(_armor(chain[0]), 0.0, 0.001, "d = 0: armor untouched")
	assert_almost_eq(_armor(chain[1]), 5.0, 0.001, "d = 1: v")
	assert_almost_eq(_armor(chain[2]), 5.0, 0.001, "d = 2: v")


## A NaN result is dropped under EVERY discard mode, before the policy runs.
func test_nan_is_dropped_under_every_discard_mode(params = use_parameters([
		AuraEffect.Discard.NONE, AuraEffect.Discard.ZERO, AuraEffect.Discard.NEGATIVE,
		AuraEffect.Discard.NON_POSITIVE, AuraEffect.Discard.POSITIVE, AuraEffect.Discard.NON_NEGATIVE])) -> void:
	var chain := _chain(2)
	var ent: Entity = await _spawn_owning(chain[0], chain)
	ent.grant_effect(_aura(_expr("NAN"), 1, [_armor_mod(5.0)], params))
	assert_eq(_grant_rows(chain[0]), 0, "discard %d: NaN never lands" % params)
	assert_eq(_grant_rows(chain[1]), 0, "discard %d: NaN never lands" % params)


## Hop auras repeat their inputs: over a 200-node star with reach 1 the
## formula sees `d ∈ {0, 1}` and three authored values, so one recompute
## needs at most (max_hops + 1) × 4 × leaves evaluations, never one per node.
func test_hop_aura_evaluates_once_per_distinct_input_tuple() -> void:
	var star := _star(199)
	var ent: Entity = await _spawn_owning(star[0], star)
	var scale := CountingScale.new()
	scale.formula = "v * (2 - d)"
	var leaves: Array[StatModifier] = [_armor_mod(1.0), _armor_mod(2.0), _armor_mod(3.0)]
	var aura := _aura(scale, 1, leaves)
	scale.calls = 0
	ent.grant_effect(aura)
	assert_almost_eq(_armor(star[1]), 6.0, 0.001, "every leaf still lands at d = 1")
	assert_almost_eq(_armor(star[0]), 12.0, 0.001, "every leaf still lands at d = 0")
	assert_lte(scale.calls, (1 + 1) * 4 * 3, "≤ (max_hops + 1) × 4 × leaves evaluations, got %d" % scale.calls)
	assert_gt(scale.calls, 0, "the spy saw the recompute at all")


## Continuous `e` never repeats, so a euclid-reading formula is not memoised —
## and still evaluates correctly per node.
func test_euclid_reading_formula_skips_the_memo_and_stays_correct() -> void:
	var chain := _chain(3)
	var ent: Entity = await _spawn_owning(chain[0], chain)
	var scale := CountingScale.new()
	scale.formula = "e / 100"
	scale.calls = 0
	ent.grant_effect(_aura(scale, 2, [_armor_mod(1.0)]))
	assert_eq(scale.calls, 3, "one evaluation per node, nothing memoised")
	assert_almost_eq(_armor(chain[2]), 2.0, 0.001, "e = 200 px at N2")
