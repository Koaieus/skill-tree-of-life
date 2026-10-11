extends GutTest

## A [CureInstance] survives `AttackRecord.capture -> rebuild` with its defs,
## counts and heal intact — or a peer's replay drops the cure (or, through
## rebuild's damage fallback, lands it as damage). Two cures with a status hit
## between them pin the flattened offsets.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _POISON := preload("res://effects/status/poison.tres")
const _TEST_DEF := preload("res://test/fixtures/status/test_status.tres")

var _graph: Graph
var _nodes: Array[SkillNode] = []
var _attacker: Entity


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_nodes.clear()
	for i in 3:
		var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
		node.name = "n%d" % i
		_graph.add_skill_node(node)
		node.global_position = Vector2(i * 100, 0)
		_nodes.append(node)
	for i in 2:
		_graph.add_edge(_nodes[i], _nodes[i + 1])
	_attacker = Entity.new()
	_attacker.display_name = "Attacker"
	_graph.entities_container.add_child(_attacker)
	await get_tree().process_frame


## A landed cure as capture sees it: the heal on effective_amount.
func _cure(target: SkillNode, entries: Array, heal: float) -> CureInstance:
	var c := CureInstance.new()
	for e: Array in entries:
		c.add(e[0], e[1])
	c.heal = heal
	c.amount = heal
	c.effective_amount = heal
	c.target = target
	c.origin = _nodes[0]
	c.attacker = _attacker
	return c


func _outcome() -> AttackOutcome:
	var o := AttackOutcome.new()
	var first := _cure(_nodes[1], [[_POISON, 2.0], [_TEST_DEF, 1.0]], 3.0)
	var status := StatusInstance.new()
	status.def = _POISON
	status.target = _nodes[2]
	status.effective_amount = 1.0
	var second := _cure(_nodes[2], [[_TEST_DEF, 4.0]], 0.0)
	o.hits.assign([first, status, second])
	return o


func _rebuilt() -> AttackOutcome:
	return AttackRecord.rebuild(AttackRecord.capture(_outcome(), _graph), _graph)


func test_a_cure_rebuilds_as_a_cure_instance() -> void:
	var hits := _rebuilt().hits
	assert_eq(hits.size(), 3)
	assert_true(hits[0] is CureInstance, "kind CURE rebuilds a CureInstance, never damage")
	assert_true(hits[1] is StatusInstance)
	assert_true(hits[2] is CureInstance)


func test_defs_counts_and_heal_survive_in_order() -> void:
	var hits := _rebuilt().hits
	var first := hits[0] as CureInstance
	var second := hits[2] as CureInstance
	assert_not_null(first)
	assert_not_null(second)
	if first == null or second == null:
		return
	assert_eq(first.defs.size(), 2)
	assert_eq(first.defs[0], _POISON as StatusDef, "first def by path")
	assert_eq(first.defs[1], _TEST_DEF as StatusDef, "second def by path")
	assert_eq(first.cleared, PackedFloat64Array([2.0, 1.0]))
	assert_almost_eq(first.heal, 3.0, 0.0001)
	assert_eq(second.defs.size(), 1, "the second cure's slice starts past the first's")
	assert_eq(second.defs[0], _TEST_DEF as StatusDef)
	assert_eq(second.cleared, PackedFloat64Array([4.0]))
	assert_almost_eq(second.heal, 0.0, 0.0001)
	assert_eq(first.target, _nodes[1])
	assert_eq(second.target, _nodes[2])


func test_capture_rebuild_capture_is_stable() -> void:
	var first := AttackRecord.capture(_outcome(), _graph)
	var second := AttackRecord.capture(AttackRecord.rebuild(first, _graph), _graph)
	assert_eq(second.hash(), first.hash(), "a re-capture of the rebuilt cure is the same record")


func test_a_record_without_cures_carries_no_cure_keys() -> void:
	var o := AttackOutcome.new()
	var heal := HealInstance.new()
	heal.target = _nodes[1]
	o.hits.assign([heal])
	var d := AttackRecord.capture(o, _graph)
	for key in [AttackRecord.KEY_CURE_COUNT, AttackRecord.KEY_CURE_DEF, AttackRecord.KEY_CURE_CLEARED]:
		assert_false(d.has(key), "cure columns are omitted at default (%s)" % key)
