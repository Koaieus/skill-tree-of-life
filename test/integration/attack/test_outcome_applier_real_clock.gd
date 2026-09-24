extends GutTest

## #504 design B, the real-clock half: [OutcomeApplier] on a
## [method BeatClock.for_tree] clock lands each hit AT its own `arrival_time`,
## in order. The wall clock is the subject here, so this lives in the
## integration tier; the instant-clock, ordering and drain properties are
## unit tests in test/unit/attack/test_outcome_applier_beat_clock.gd.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _graph: Graph
var _owner: Entity
var _nodes: Array[SkillNode] = []


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_owner = Entity.new()
	_owner.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_owner)
	await get_tree().process_frame
	_nodes = []
	for i in 3:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.position = Vector2(i * 100, 0)
		_graph.add_skill_node(sn)
		sn.owned_by = _owner
		_nodes.append(sn)
	await get_tree().process_frame


## A TRUE-typed DamageInstance: `Mitigation.apply` returns the raw amount
## unchanged for TRUE, so the fixture's HP arithmetic is exact rather than
## armour-dependent (see `.claude/rules/turn-manager.md`).
## #543: the fixture authors a STRUCTURAL key, and the applier compiles it
## into seconds. These outcomes carry the default
## [constant ScheduleEntry.Cadence.LITERAL], where the key IS the second — so
## every number below still means exactly what it did when it was written
## straight into `arrival_time`, but it now travels the production route
## (compile, then wait) instead of bypassing it.
func _hit(target: SkillNode, amount: float, arrival_time: float) -> DamageInstance:
	var d := DamageInstance.new()
	d.target = target
	d.amount = amount
	d.type = DamageInstance.Type.TRUE
	d.structural_key = arrival_time
	return d


func _outcome(hits: Array[DamageInstance]) -> AttackOutcome:
	var o := AttackOutcome.new()
	for h in hits:
		o.hits.append(h)
	return o


func test_real_clock_lands_each_hit_at_its_own_arrival_time() -> void:
	var landed: Array[SkillNode] = []
	var handler := func(node: SkillNode, _amount: float, _source: Variant) -> void:
		landed.append(node)
	Events.skill_node_damaged.connect(handler)

	var outcome := _outcome([
		_hit(_nodes[0], 3.0, 0.0),
		_hit(_nodes[1], 3.0, 0.15),
		_hit(_nodes[2], 3.0, 0.30),
	])
	OutcomeApplier.apply(outcome, CombatWorld.live(), BeatClock.for_tree(get_tree()))

	assert_eq(landed.size(), 1, "only the t=0 hit lands before any waiting")
	await get_tree().create_timer(0.20).timeout
	assert_eq(landed.size(), 2, "the 0.15s hit has landed; the 0.30s one has not")
	await get_tree().create_timer(0.25).timeout
	Events.skill_node_damaged.disconnect(handler)
	assert_eq(landed, _nodes, "all three landed, in arrival order")
