extends GutTest

## StatusInstance (#878): [method land_on] against a shadow leaves the real
## node untouched (`.claude/rules/attack-timeline.md`) and against the live
## world lands [method NodeCombat.apply_status] for real.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _TEST_DEF := preload("res://test/fixtures/status/test_status.tres")
## Same shape with `potency_stat_id` / `resistance_stat_id` naming the poison
## pair (#963) — a `.tres` so it survives an AttackRecord round trip by path.
const _SCALED_DEF := preload("res://test/fixtures/status/test_scaled_status.tres")
const _POISON := preload("res://effects/status/poison.tres")
const _BLINDNESS := preload("res://effects/status/blindness.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _node: SkillNode
var _attacker: Entity
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

	_attacker = autofree(Entity.new())
	_attacker.display_name = "Attacker"
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_attacker)


func after_each() -> void:
	for w in _worlds:
		w.free_shadow()


func _shadow() -> CombatWorld:
	var w := CombatWorld.shadow()
	_worlds.append(w)
	return w


func _status_hit(power: float = 2.0, def: StatusDef = _TEST_DEF) -> StatusInstance:
	var hit := StatusInstance.new()
	hit.def = def
	hit.power = power
	hit.target = _node
	return hit


## A power-2 hit of the scaled def from `_attacker`, with the potency /
## resistance pair set on the two boards (hand-built objects, never authored
## content): 2 × 1.21 × (1 − 0.3) = 1.694.
func _scaled_hit(potency: float = 1.21, resistance: float = 0.3) -> StatusInstance:
	_attacker.stat_board.get_stat(&"poison_potency").base_value = potency
	_entity.stat_board.get_stat(&"poison_resistance").base_value = resistance
	var hit := _status_hit(2.0, _SCALED_DEF)
	hit.attacker = _attacker
	return hit


func _resistance_mod(add: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = &"poison_resistance"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = add
	return m


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


# ── Potency × (1 − resistance), once, at land (#963) ─────────────────────────

func test_land_scales_power_by_attacker_potency_and_node_resistance() -> void:
	var hit := _scaled_hit(1.21, 0.3)
	OutcomeApplier.land_one(hit, CombatWorld.live())
	assert_almost_eq(_node.get_combat().get_status_power(&"test_scaled_status"), 1.694, 0.0001,
			"2 × 1.21 × (1 − 0.3)")
	assert_almost_eq(hit.effective_amount, 1.694, 0.0001,
			"the LANDED stacks ride effective_amount — that is what the record ships")


func test_a_null_attacker_scales_potency_by_one() -> void:
	var hit := _scaled_hit(1.21, 0.3)
	hit.attacker = null
	OutcomeApplier.land_one(hit, CombatWorld.live())
	assert_almost_eq(_node.get_combat().get_status_power(&"test_scaled_status"), 1.4, 0.0001,
			"2 × 1 × 0.7")


func test_blank_ids_leave_power_unscaled() -> void:
	# Both boards carry the pair, but the def does not name it.
	_attacker.stat_board.get_stat(&"poison_potency").base_value = 1.21
	_entity.stat_board.get_stat(&"poison_resistance").base_value = 0.3
	var hit := _status_hit(2.0, _TEST_DEF)
	hit.attacker = _attacker
	OutcomeApplier.land_one(hit, CombatWorld.live())
	assert_almost_eq(_node.get_combat().get_status_power(&"test_status"), 2.0, 0.0001)


## A poison hit of [param per_hit] from `_attacker`, potency 1.21 and the
## defender's resistance 0.3, with the two flat extra-stacks stats set.
func _poison_hit(per_hit: float, family_extra: float, umbrella_extra: float) -> StatusInstance:
	_attacker.stat_board.get_stat(&"poison_potency").base_value = 1.21
	_entity.stat_board.get_stat(&"poison_resistance").base_value = 0.3
	_attacker.stat_board.get_stat(&"poison_stacks_per_hit").base_value = family_extra
	_attacker.stat_board.get_stat(&"dot_stacks_per_hit").base_value = umbrella_extra
	var hit := _status_hit(per_hit, _POISON)
	hit.attacker = _attacker
	return hit


func test_family_extra_stacks_add_flat_before_potency() -> void:
	var hit := _poison_hit(0.5, 1.0, 0.0)
	OutcomeApplier.land_one(hit, CombatWorld.live())
	assert_almost_eq(_node.get_combat().get_status_power(&"poison"), 1.5 * 1.21 * 0.7, 0.0001,
			"(0.5 + 1) × 1.21 × (1 − 0.3)")
	assert_almost_eq(hit.effective_amount, 1.5 * 1.21 * 0.7, 0.0001)


func test_the_umbrella_sums_with_the_family_stat_before_potency() -> void:
	var hit := _poison_hit(0.5, 1.0, 0.5)
	OutcomeApplier.land_one(hit, CombatWorld.live())
	assert_almost_eq(_node.get_combat().get_status_power(&"poison"), 2.0 * 1.21 * 0.7, 0.0001,
			"(0.5 + 1 + 0.5) × 1.21 × (1 − 0.3)")


func test_blindness_ignores_the_dot_extra_stacks() -> void:
	_attacker.stat_board.get_stat(&"poison_stacks_per_hit").base_value = 1.0
	_attacker.stat_board.get_stat(&"dot_stacks_per_hit").base_value = 0.5
	var hit := _status_hit(1.0, _BLINDNESS)
	hit.attacker = _attacker
	OutcomeApplier.land_one(hit, CombatWorld.live())
	assert_almost_eq(_node.get_combat().get_status_power(&"blindness"), 1.0, 0.0001,
			"blindness lists no extra-stacks stat")


func test_blindness_scales_by_its_own_potency_and_resistance() -> void:
	_attacker.stat_board.get_stat(&"blindness_potency").base_value = 2.0
	_entity.stat_board.get_stat(&"blindness_resistance").base_value = 0.25
	var hit := _status_hit(1.0, _BLINDNESS)
	hit.attacker = _attacker
	OutcomeApplier.land_one(hit, CombatWorld.live())
	assert_almost_eq(_node.get_combat().get_status_power(&"blindness"), 1.5, 0.0001,
			"1 × 2 × (1 − 0.25)")


func test_a_shadow_land_reads_the_shadow_nodes_resistance_never_the_live_one() -> void:
	# Live defender at 0.3; the shadow node alone carries +0.5 more → 0.8.
	var hit := _scaled_hit(1.21, 0.3)
	var w := _shadow()
	var shadow := w.combat_for(_node)
	shadow.add_local_modifier(_resistance_mod(0.5))
	assert_almost_eq(float(shadow.get_local_value(&"poison_resistance")), 0.8, 0.0001,
			"sanity: the shadow-local modifier is on the shadow")
	assert_almost_eq(float(_node.get_local_value(&"poison_resistance")), 0.3, 0.0001,
			"sanity: the live node never saw it")

	OutcomeApplier.land_one(hit, w)
	assert_almost_eq(shadow.get_status_power(&"test_scaled_status"), 2.0 * 1.21 * 0.2, 0.0001,
			"the shadow landing scaled by the SHADOW's resistance (0.8)")
	assert_almost_eq(_node.get_combat().get_status_power(&"test_scaled_status"), 0.0, 0.0001,
			"the live node is untouched by a shadow landing")


func test_the_record_replays_the_landed_stacks_never_rescaling_on_the_peer() -> void:
	# Authority: 1.694 lands. The peer's boards would scale it again (the
	# rebuilt hit resolves its attacker, and the peer node has a resistance)
	# unless the rebuilt hit carries the number FLAT — the PERCENT_MAX
	# precedent (hit_instance.gd `basis`).
	var outcome := AttackOutcome.new()
	outcome.hits.append(_scaled_hit(1.21, 0.3))
	OutcomeApplier.apply(outcome, CombatWorld.live())
	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, _graph)))
	assert_almost_eq(wired[AttackRecord.KEY_HIT_AMOUNT][0], 1.694, 0.0001,
			"the record ships the landed stacks")

	var peer_graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(peer_graph)
	var peer_alloc := AllocationSystem.new()
	peer_alloc.graph = peer_graph
	add_child_autofree(peer_alloc)
	var peer_entity: Entity = autofree(Entity.new())
	peer_entity.display_name = "PeerDefender"
	peer_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	# The peer's defender is MORE resistant than the authority saw — a second
	# scaling pass would show up as 1.694 × 0.5.
	peer_entity.stat_board.get_stat(&"poison_resistance").base_value = 0.5
	peer_graph.add_child(peer_entity)
	var peer_node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	peer_graph.skill_nodes_container.add_child(peer_node)
	await get_tree().process_frame
	peer_alloc.force_allocate(peer_entity, peer_node)
	peer_entity.core_location = peer_node
	peer_graph.get_stable_id(peer_node)
	_graph.get_stable_id(_node)

	var rebuilt := AttackRecord.rebuild(wired, peer_graph)
	assert_eq(rebuilt.hits.size(), 1)
	OutcomeApplier.apply(rebuilt, CombatWorld.live())
	assert_almost_eq(peer_node.get_combat().get_status_power(&"test_scaled_status"), 1.694, 0.0001,
			"the peer lands exactly what the authority landed — no second scaling pass")


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
