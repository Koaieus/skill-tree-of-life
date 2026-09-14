extends GutTest

## StatusInstance (#878): [method land_on] against a shadow leaves the real
## node untouched (`.claude/rules/attack-timeline.md`) and against the live
## world lands [method NodeCombat.apply_status] for real.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _TEST_DEF := preload("res://test/fixtures/status/test_status.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _node: SkillNode
var _worlds: Array[CombatWorld] = []


func before_each() -> void:
	_worlds = []
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.display_name = "Defender"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)

	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(_node)
	await get_tree().process_frame

	_alloc.force_allocate(_entity, _node)
	_entity.core_location = _node


func after_each() -> void:
	for w in _worlds:
		w.free_shadow()


func _shadow() -> CombatWorld:
	var w := CombatWorld.shadow()
	_worlds.append(w)
	return w


func _status_hit(power: float = 2.0) -> StatusInstance:
	var hit := StatusInstance.new()
	hit.def = _TEST_DEF
	hit.power = power
	hit.target = _node
	return hit


func test_land_on_a_shadow_leaves_the_live_node_untouched() -> void:
	var w := _shadow()
	var slice := w.combat_for(_node)
	OutcomeApplier.land_one(_status_hit(2.0), w)
	assert_almost_eq(slice.get_status_power(&"test_status"), 2.0, 0.0001,
			"the shadow slice must carry the status")
	assert_almost_eq(_node.get_combat().get_status_power(&"test_status"), 0.0, 0.0001,
			"the real node must be untouched by a shadow landing")


func test_land_on_the_live_world_applies_it_for_real() -> void:
	OutcomeApplier.land_one(_status_hit(3.0), CombatWorld.live())
	assert_almost_eq(_node.get_combat().get_status_power(&"test_status"), 3.0, 0.0001,
			"a live landing must actually apply the status")


func test_land_on_carries_power_into_amount_and_effective_amount() -> void:
	var hit := _status_hit(1.5)
	OutcomeApplier.land_one(hit, CombatWorld.live())
	assert_almost_eq(hit.amount, 1.5, 0.0001)
	assert_almost_eq(hit.effective_amount, 1.5, 0.0001,
			"AttackRecord.capture reads effective_amount generically — a status must ride it")


func test_the_record_round_trip_lands_the_status_live_on_a_second_world() -> void:
	# The trap this pins: AttackRecord never replays outcome.hits in memory —
	# it captures a Dictionary of scalars and REBUILDS a fresh StatusInstance
	# from it (docs/domain/multiplayer-sync-model.md), so the def must survive
	# as a resource_path, never a live reference, and the rebuilt hit's kind
	# must come back as STATUS or it gets mis-decoded as a 0-damage hit.
	var outcome := AttackOutcome.new()
	outcome.hits.append(_status_hit(2.0))
	OutcomeApplier.apply(outcome, CombatWorld.live())
	assert_almost_eq(_node.get_combat().get_status_power(&"test_status"), 2.0, 0.0001,
			"sanity: the direct landing must have worked before testing its record")

	var d := AttackRecord.capture(outcome, _graph)
	# The real wire proof: var_to_bytes cannot encode a live Object without
	# `full_objects`, so surviving this round trip proves no live reference —
	# in particular no live StatusDef — snuck into the dictionary.
	var wired: Dictionary = bytes_to_var(var_to_bytes(d))
	assert_eq(wired[AttackRecord.KEY_HIT_STATUS_DEF][0], _TEST_DEF.resource_path,
			"the def crosses as a path, not a reference")

	# A second, otherwise-untouched node/graph stands in for a peer. Must be
	# ALLOCATED like `_node` — `apply_status` is a no-op on an unallocated node
	# for a `CLEAR` def (#872), and the fixture def is `CLEAR`.
	var peer_graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(peer_graph)
	var peer_alloc := AllocationSystem.new()
	peer_alloc.graph = peer_graph
	add_child_autofree(peer_alloc)
	var peer_entity: Entity = autofree(Entity.new())
	peer_entity.display_name = "PeerDefender"
	peer_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	peer_graph.add_child(peer_entity)
	var peer_node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	peer_graph.skill_nodes_container.add_child(peer_node)
	await get_tree().process_frame
	peer_alloc.force_allocate(peer_entity, peer_node)
	peer_entity.core_location = peer_node
	# Force the same stable_id sequence as `_graph` so `_node_of` resolves.
	peer_graph.get_stable_id(peer_node)
	_graph.get_stable_id(_node)

	var rebuilt := AttackRecord.rebuild(wired, peer_graph)
	assert_eq(rebuilt.hits.size(), 1)
	assert_true(rebuilt.hits[0] is StatusInstance,
			"kind STATUS must rebuild as a StatusInstance, not fall into the DamageInstance else-branch")
	var peer_target := (rebuilt.hits[0] as StatusInstance).target
	assert_almost_eq(peer_target.get_combat().get_status_power(&"test_status"), 0.0, 0.0001,
			"rebuild alone must not have landed anything yet")
	OutcomeApplier.apply(rebuilt, CombatWorld.live())
	assert_almost_eq(peer_target.get_combat().get_status_power(&"test_status"), 2.0, 0.0001,
			"replaying the record must land the status live")
