extends GutTest

## RevealInstance (#1033): a shadow land is a no-op, a live land emits
## [signal Events.node_scouted] once with (node, attacker, radius), and the
## hit survives an [AttackRecord] round trip as its own kind — a peer replays
## the reveal from the record, never from a DamageInstance's ammo.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _graph: Graph
var _node: SkillNode
var _attacker: Entity
var _worlds: Array[CombatWorld] = []


func before_each() -> void:
	_worlds = []
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(_node)
	_attacker = autofree(Entity.new())
	_attacker.display_name = "Scout"
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(_attacker)  # entity_id is minted on entry here
	await get_tree().process_frame
	watch_signals(Events)


func after_each() -> void:
	for w in _worlds:
		w.free_shadow()


func _reveal(radius: float) -> RevealInstance:
	var hit := RevealInstance.new()
	hit.amount = radius
	hit.attacker = _attacker
	hit.target = _node
	return hit


func test_kind_is_reveal() -> void:
	assert_eq(_reveal(200.0).kind, HitInstance.Kind.REVEAL)


func test_land_on_a_shadow_emits_nothing() -> void:
	var w := CombatWorld.shadow()
	_worlds.append(w)
	OutcomeApplier.land_one(_reveal(200.0), w)
	assert_signal_not_emitted(Events, "node_scouted", "a shadow land must not reveal")


func test_land_on_the_live_world_emits_once_with_node_attacker_radius() -> void:
	OutcomeApplier.land_one(_reveal(200.0), CombatWorld.live())
	assert_signal_emit_count(Events, "node_scouted", 1)
	assert_signal_emitted_with_parameters(Events, "node_scouted", [_node, _attacker, 200.0])


func test_the_record_round_trips_a_reveal_as_its_own_kind() -> void:
	var outcome := AttackOutcome.new()
	outcome.hits.append(_reveal(230.0))
	OutcomeApplier.apply(outcome, CombatWorld.live())
	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, _graph)))
	var rebuilt := AttackRecord.rebuild(wired, _graph)
	assert_eq(rebuilt.hits.size(), 1)
	var hit := rebuilt.hits[0] as RevealInstance
	assert_not_null(hit, "a recorded REVEAL rebuilds as a RevealInstance")
	if hit == null:
		return
	assert_eq(hit.kind, HitInstance.Kind.REVEAL)
	assert_almost_eq(hit.amount, 230.0, 0.0001, "the radius rides `amounts`")
	assert_eq(hit.attacker, _attacker, "the firer rides `attackers`")
	assert_eq(hit.target, _node, "the landing node rides `targets`")
