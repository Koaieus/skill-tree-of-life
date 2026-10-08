extends GutTest

## An aimed cast's [member AttackOutcome.aim] survives the [AttackRecord]
## round-trip, so a peer draws the same hitscan streak; a node cast carries
## none. The streak fits inside the lead-in, so an aimed cast's first impact
## lands exactly when a node cast's of the same tempo does.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _nodes: Array[SkillNode] = []


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_nodes.clear()
	for i in 2:
		var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
		node.name = "n%d" % i
		_graph.add_skill_node(node)
		_nodes.append(node)
	_graph.add_edge(_nodes[0], _nodes[1])
	await get_tree().process_frame


func _outcome(aimed: bool) -> AttackOutcome:
	var hit := DamageInstance.new()
	hit.origin = _nodes[0]
	hit.target = _nodes[1]
	hit.effective_amount = 2.0
	var ev := PropagationEvent.new()
	ev.origin = _nodes[0]
	ev.target = _nodes[1]
	ev.beat = 0
	ev.hits.append(hit)
	var o := AttackOutcome.new()
	o.hits.assign([hit])
	o.timeline.append(ev)
	if aimed:
		var aim := AttackOutcome.Aim.new()
		aim.origin = _nodes[0]
		aim.angle = 0.7853981633974483
		aim.length = 312.625
		o.aim = aim
	return o


func test_aim_round_trips_exactly() -> void:
	var rebuilt := AttackRecord.rebuild(AttackRecord.capture(_outcome(true), _graph), _graph)
	assert_not_null(rebuilt.aim, "an aimed outcome rebuilds with its aim")
	if rebuilt.aim == null:
		return
	assert_eq(rebuilt.aim.origin, _nodes[0], "origin node")
	assert_eq(rebuilt.aim.angle, 0.7853981633974483, "angle, exact")
	assert_eq(rebuilt.aim.length, 312.625, "length, exact")


func test_node_cast_has_no_aim() -> void:
	var rebuilt := AttackRecord.rebuild(AttackRecord.capture(_outcome(false), _graph), _graph)
	assert_null(rebuilt.aim, "a node-targeted outcome carries no aim")


func test_aimed_first_impact_matches_node_cast() -> void:
	var tempo := PresentationTempo.shared_default()
	var aimed := OutcomeSchedule.compile(_outcome(true), tempo, 1.0)
	var plain := OutcomeSchedule.compile(_outcome(false), tempo, 1.0)
	assert_false(aimed.entries.is_empty())
	assert_eq(aimed.entries[0].arrive_at, plain.entries[0].arrive_at,
			"the streak lives inside the lead-in; beat 0 does not move")
