extends GutTest

## A hit's arrow type survives the [AttackRecord] round-trip: the id rides a
## column, so a peer's rebuilt (plain) hits still know which [AmmoType] flew.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _ROSTER := preload("res://attack/ammo/ammo_type_roster.tres")

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


func _arrow(type_id: StringName) -> DamageInstance:
	var hit := RangedDamageFormula.compute(null, _nodes[0], _nodes[1], _ROSTER.by_id(type_id))
	hit.effective_amount = 3.0
	return hit


func test_ammo_type_ids_round_trip() -> void:
	var poison := _arrow(&"poison")
	var status := RangedDamageFormula.riders_for(poison)[0] as StatusInstance
	var base := _arrow(&"arrow")
	var spell := DamageInstance.new()
	spell.target = _nodes[1]
	spell.origin = _nodes[0]
	var o := AttackOutcome.new()
	o.hits.assign([poison, status, base, spell])
	var rebuilt := AttackRecord.rebuild(AttackRecord.capture(o, _graph), _graph)
	assert_eq(rebuilt.hits.size(), 4)
	assert_eq(rebuilt.hits[0].ammo_type_id, &"poison", "poison damage hit")
	assert_eq(rebuilt.hits[1].ammo_type_id, &"poison", "poison status hit")
	assert_eq(rebuilt.hits[2].ammo_type_id, &"arrow", "base arrow")
	assert_eq(rebuilt.hits[3].ammo_type_id, &"", "spell hit is not an arrow")
