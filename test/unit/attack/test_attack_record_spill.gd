extends GutTest

## An attack's spill rides its [DeallocEntry]s across the wire and the live
## replay RECEIVES it: [AttackRecord] round-trips each entry's transfers, and a
## replay lands the recorded amounts rather than computing its own.
## Curse is the authored spiller (SpillSpread, Mine).

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _CURSE := preload("res://effects/status/curse.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _a: Entity


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_a = Entity.new()
	_a.name = "A"
	_a.display_name = "A"
	_a.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(_a)
	await get_tree().process_frame


## C–1–2–3, all A's, C the core.
func _chain(count: int) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	for i in count:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.position = Vector2(i * 100, 0)
		_graph.add_skill_node(sn)
		out.append(sn)
	for i in count - 1:
		_graph.add_edge(out[i], out[i + 1])
	await get_tree().process_frame
	_alloc.force_allocate(_a, out[0])
	_a.core_location = out[0]
	for i in range(1, count):
		_alloc.force_allocate(_a, out[i])
	return out


func _kill(target: SkillNode) -> AttackOutcome:
	var o := AttackOutcome.new()
	var d := DamageInstance.new()
	d.target = target
	d.amount = 1.0e6
	d.type = DamageInstance.Type.TRUE
	d.structural_key = 0.0
	o.hits.append(d)
	return o


## Every transfer on [param outcome]'s entries as `[from id, to id (0 = burned),
## def path, amount]`, in entry order.
func _spill_of(outcome: AttackOutcome) -> Array:
	var out := []
	for hit in outcome.hits:
		for e in hit.deallocations:
			for k in e.spill.size():
				var t := e.spill[k]
				var to_real: SkillNode = t.to.real() if t.to != null else null
				out.append([e.node_id, to_real.stable_id if to_real != null else 0,
						e.spill_defs[k].resource_path, t.amount])
	return out


## Kill 2 in the shadow: 2's curse spills onto 1, 3 (islanded) has none.
func _computed(n: Array[SkillNode]) -> AttackOutcome:
	n[2].get_combat().apply_status(_CURSE, 4.0)
	var outcome := _kill(n[2])
	var shadow := CombatWorld.shadow()
	OutcomeApplier.apply(outcome, shadow)
	shadow.free_shadow()
	return outcome


func _wired(outcome: AttackOutcome) -> Dictionary:
	return bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, _graph)))


func test_spill_round_trips_through_the_record() -> void:
	var n := await _chain(4)
	var outcome := _computed(n)
	var computed := _spill_of(outcome)
	assert_eq(computed, [[n[2].stable_id, n[1].stable_id, _CURSE.resource_path, 4.0]],
			"the shadow flush writes 2's spill onto 2's entry")
	var rebuilt := AttackRecord.rebuild(_wired(outcome), _graph)
	assert_eq(_spill_of(rebuilt), computed, "rebuilt entries carry identical transfers")


func test_the_live_replay_lands_the_recorded_amount_not_its_own() -> void:
	var n := await _chain(4)
	var rebuilt := AttackRecord.rebuild(_wired(_computed(n)), _graph)
	var altered := 0
	for hit in rebuilt.hits:
		for e in hit.deallocations:
			for t in e.spill:
				t.amount = 2.0
				altered += 1
	assert_eq(altered, 1, "precondition: the record carries 2's one transfer")

	var battle := BattleSystem.new()
	battle.allocation_system = _alloc
	battle.graph = _graph
	add_child_autofree(battle)
	OutcomeApplier.apply(rebuilt, CombatWorld.live(), null, _alloc)
	assert_false(n[2].is_allocated(), "precondition: the replay stripped 2")
	assert_almost_eq(n[1].get_combat().get_status_power(&"curse"), 2.0, 0.0001,
			"1 holds the RECORDED 2, not a recomputed 4")
