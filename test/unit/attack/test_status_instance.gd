extends GutTest

## StatusInstance (#878): [method land_on] against a shadow leaves the real
## node untouched (`.claude/rules/attack-timeline.md`) and against the live
## world lands [method NodeCombat.apply_status] for real.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _TEST_DEF := preload("res://test/fixtures/status/test_status.tres")
## Same shape with `stacks_stat_id` / `resistance_stat_id` naming the poison
## pair — a `.tres` so it survives an AttackRecord round trip by path.
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


## A power-2 hit of the scaled def from `_attacker`, with the stacks INCREASE
## / resistance pair set on the two boards (hand-built objects, never authored
## content): [param scale] 1.3 is +30% on `poison_stacks_per_hit`, so
## 2 × 1.3 = 2.6 lands 3 (half-up, ADR 0032) — resistance below 100% filters
## on the host later.
func _scaled_hit(scale: float = 1.3, resistance: float = 0.3) -> StatusInstance:
	_attacker.stat_board.add_modifier(_mod(&"poison_stacks_per_hit",
			StatModifier.Operation.INCREASE, (scale - 1.0) * 100.0))
	_entity.stat_board.get_stat(&"poison_resistance").base_value = resistance
	var hit := _status_hit(2.0, _SCALED_DEF)
	hit.attacker = _attacker
	return hit


func _mod(stat_id: StringName, op: StatModifier.Operation, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = op
	m.value = value
	return m


func _add_base(stat_id: StringName, value: float) -> StatModifier:
	return _mod(stat_id, StatModifier.Operation.ADD_BASE, value)


func _resistance_mod(add: float) -> StatModifier:
	return _add_base(&"poison_resistance", add)


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
	var hit := _status_hit(2.0)
	OutcomeApplier.land_one(hit, CombatWorld.live())
	assert_almost_eq(hit.amount, 2.0, 0.0001)
	assert_almost_eq(hit.effective_amount, 2.0, 0.0001,
			"AttackRecord.capture reads effective_amount generically — a status must ride it")


# ── One fold of the stacks stat, once, at land; resistance filters later ────
#
# The authored per-hit power is a `base_add` overlay on the attacker's stacks
# stat (ADR 0029): its flats add to it, its INCREASE / MORE scale it, and its
# `parent_ids` fold `dot_stacks_per_hit` in the same read.

func test_land_scales_by_the_stacks_increase_and_ignores_resistance_below_100() -> void:
	var hit := _scaled_hit(1.3, 0.3)
	OutcomeApplier.land_one(hit, CombatWorld.live())
	assert_almost_eq(_node.get_combat().get_status_power(&"test_scaled_status"), 3.0, 0.0001,
			"2 × 1.3 = 2.6 → 3; the 0.3 resistance filters on the host at effect time, never here")
	assert_almost_eq(hit.effective_amount, 3.0, 0.0001,
			"the LANDED stacks ride effective_amount — that is what the record ships")


func test_a_null_attacker_lands_the_authored_amount() -> void:
	var hit := _scaled_hit(1.3, 0.3)
	hit.attacker = null
	OutcomeApplier.land_one(hit, CombatWorld.live())
	assert_almost_eq(_node.get_combat().get_status_power(&"test_scaled_status"), 2.0, 0.0001,
			"2 × 1; resistance never touches the landing")


func test_blank_ids_leave_power_unscaled() -> void:
	# Both boards carry the pair, but the def does not name it.
	_attacker.stat_board.add_modifier(_mod(&"poison_stacks_per_hit",
			StatModifier.Operation.INCREASE, 21.0))
	_entity.stat_board.get_stat(&"poison_resistance").base_value = 0.3
	var hit := _status_hit(2.0, _TEST_DEF)
	hit.attacker = _attacker
	OutcomeApplier.land_one(hit, CombatWorld.live())
	assert_almost_eq(_node.get_combat().get_status_power(&"test_status"), 2.0, 0.0001)


## A poison hit of [param per_hit] from `_attacker`; no resistance.
func _poison_hit(per_hit: float) -> StatusInstance:
	var hit := _status_hit(per_hit, _POISON)
	hit.attacker = _attacker
	return hit


func test_a_49_percent_increase_rounds_half_up_to_1() -> void:
	_attacker.stat_board.add_modifier(_mod(&"poison_stacks_per_hit",
			StatModifier.Operation.INCREASE, 49.0))
	var hit := _poison_hit(1.0)
	OutcomeApplier.land_one(hit, CombatWorld.live())
	assert_almost_eq(hit.effective_amount, 1.0, 0.0001, "1 authored × +49% = 1.49 → 1 (ADR 0032)")
	assert_almost_eq(_node.get_combat().get_status_power(&"poison"), 1.0, 0.0001)


func test_a_flat_on_the_umbrella_reaches_poison() -> void:
	_attacker.stat_board.add_modifier(_add_base(&"dot_stacks_per_hit", 1.0))
	var hit := _poison_hit(1.0)
	OutcomeApplier.land_one(hit, CombatWorld.live())
	assert_almost_eq(_node.get_combat().get_status_power(&"poison"), 2.0, 0.0001,
			"1 authored + 1 from the parent")


func test_a_more_on_the_family_stat_scales_the_authored_amount_too() -> void:
	_attacker.stat_board.add_modifier(_mod(&"poison_stacks_per_hit",
			StatModifier.Operation.MULTIPLY, 2.0))
	_attacker.stat_board.add_modifier(_add_base(&"poison_stacks_per_hit", 1.0))
	var hit := _poison_hit(1.0)
	OutcomeApplier.land_one(hit, CombatWorld.live())
	assert_almost_eq(_node.get_combat().get_status_power(&"poison"), 4.0, 0.0001,
			"(1 authored + 1 flat) × 2")


func test_the_umbrella_folds_into_the_family_stat_exactly_once() -> void:
	_attacker.stat_board.add_modifier(_add_base(&"dot_stacks_per_hit", 2.0))
	_attacker.stat_board.add_modifier(_add_base(&"poison_stacks_per_hit", 1.0))
	var hit := _poison_hit(1.0)
	OutcomeApplier.land_one(hit, CombatWorld.live())
	assert_almost_eq(_node.get_combat().get_status_power(&"poison"), 4.0, 0.0001,
			"1 + 1 + 2, the umbrella counted once")


func test_blindness_ignores_the_umbrella_and_folds_its_own_stat() -> void:
	_attacker.stat_board.add_modifier(_add_base(&"poison_stacks_per_hit", 1.0))
	_attacker.stat_board.add_modifier(_add_base(&"dot_stacks_per_hit", 0.5))
	_attacker.stat_board.add_modifier(_mod(&"blindness_stacks_per_hit",
			StatModifier.Operation.INCREASE, 100.0))
	_entity.stat_board.get_stat(&"blindness_resistance").base_value = 0.25
	var hit := _status_hit(1.0, _BLINDNESS)
	hit.attacker = _attacker
	OutcomeApplier.land_one(hit, CombatWorld.live())
	assert_almost_eq(_node.get_combat().get_status_power(&"blindness"), 2.0, 0.0001,
			"1 × +100%, its 0.25 resistance filtering later; dot_stacks_per_hit is not blindness's parent")


func test_stacks_per_hit_answers_authored_on_a_null_board_or_blank_id() -> void:
	assert_almost_eq(_POISON.stacks_per_hit(null, 1.5), 2.0, 0.0001, "null board, rounded half-up")
	assert_almost_eq(_TEST_DEF.stacks_per_hit(_attacker.stat_board, 1.5), 2.0, 0.0001, "blank id, rounded half-up")
	_attacker.stat_board.add_modifier(_add_base(&"poison_stacks_per_hit", 1.0))
	assert_almost_eq(_POISON.stacks_per_hit(_attacker.stat_board, 1.5), 3.0, 0.0001,
			"the public fold the readout shares")


func test_a_shadow_tick_reads_the_shadow_nodes_resistance_never_the_live_one() -> void:
	# Live defender at 0.3; the shadow node alone carries +0.5 more → 0.8.
	_entity.stat_board.get_stat(&"poison_resistance").base_value = 0.3
	var w := _shadow()
	var shadow := w.combat_for(_node)
	shadow.add_local_modifier(_resistance_mod(0.5))
	assert_almost_eq(float(shadow.get_local_value(&"poison_resistance")), 0.8, 0.0001,
			"sanity: the shadow-local modifier is on the shadow")
	assert_almost_eq(float(_node.get_local_value(&"poison_resistance")), 0.3, 0.0001,
			"sanity: the live node never saw it")
	assert_gt(shadow.get_current_hp(), 10.0, "sanity: the shadow survives the tick")

	shadow.apply_status(_POISON, 10.0)
	var before := shadow.get_current_hp()
	shadow.tick_statuses()
	assert_almost_eq(before - shadow.get_current_hp(), 2.0, 0.0001,
			"the shadow tick filtered by the SHADOW's 0.8: 10 − ⌈8 − ½⌉, never the live 0.3's 7")
	assert_almost_eq(_node.get_combat().get_status_power(&"poison"), 0.0, 0.0001,
			"the live node is untouched by a shadow tick")


func test_a_shadow_land_gates_on_the_shadow_nodes_full_resistance() -> void:
	# Live at 0.3, the shadow alone at 1.0: the authority's resolve blocks.
	var hit := _scaled_hit(1.3, 0.3)
	var w := _shadow()
	var shadow := w.combat_for(_node)
	shadow.add_local_modifier(_resistance_mod(0.7))
	OutcomeApplier.land_one(hit, w)
	assert_almost_eq(hit.power, 0.0, 0.0001, "blocked on the shadow: resolved 0")
	assert_almost_eq(hit.effective_amount, 0.0, 0.0001)
	assert_almost_eq(shadow.get_status_power(&"test_scaled_status"), 0.0, 0.0001, "no row on the shadow")


## A second allocated graph standing in for a peer, its defender at
## [param resistance]; forces the same stable_id sequence as `_graph`.
func _peer_node(resistance: float) -> SkillNode:
	var peer_graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(peer_graph)
	var peer_alloc := AllocationSystem.new()
	peer_alloc.graph = peer_graph
	add_child_autofree(peer_alloc)
	var peer_entity: Entity = autofree(Entity.new())
	peer_entity.display_name = "PeerDefender"
	peer_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	peer_entity.stat_board.get_stat(&"poison_resistance").base_value = resistance
	peer_graph.add_child(peer_entity)
	var peer_node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	peer_graph.skill_nodes_container.add_child(peer_node)
	await get_tree().process_frame
	peer_alloc.force_allocate(peer_entity, peer_node)
	peer_entity.core_location = peer_node
	peer_graph.get_stable_id(peer_node)
	_graph.get_stable_id(_node)
	return peer_node


func test_the_record_replays_the_landed_stacks_never_rescaling_on_the_peer() -> void:
	# Authority: 3 lands (0.3 resistance filters at effect time, not here).
	# The peer's boards would scale it again (the rebuilt hit resolves its
	# attacker) unless the rebuilt hit carries the number FLAT — the
	# PERCENT_MAX precedent (hit_instance.gd `basis`).
	var outcome := AttackOutcome.new()
	outcome.hits.append(_scaled_hit(1.3, 0.3))
	OutcomeApplier.apply(outcome, CombatWorld.live())
	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, _graph)))
	assert_almost_eq(wired[AttackRecord.KEY_HIT_AMOUNT][0], 3.0, 0.0001,
			"the record ships the landed stacks")

	# The peer's defender sits at 100% — a second resolve would block it.
	var peer_node: SkillNode = await _peer_node(1.0)
	var rebuilt := AttackRecord.rebuild(wired, _peer_graph_of(peer_node))
	assert_eq(rebuilt.hits.size(), 1)
	OutcomeApplier.apply(rebuilt, CombatWorld.live())
	assert_almost_eq(peer_node.get_combat().get_status_power(&"test_scaled_status"), 3.0, 0.0001,
			"the peer lands exactly what the authority landed — no second resolve")


func test_a_blocked_landing_ships_0_and_the_peer_lands_nothing() -> void:
	var outcome := AttackOutcome.new()
	outcome.hits.append(_scaled_hit(1.3, 1.0))
	OutcomeApplier.apply(outcome, CombatWorld.live())
	assert_almost_eq(_node.get_combat().get_status_power(&"test_scaled_status"), 0.0, 0.0001,
			"100% blocks the authority's landing")
	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, _graph)))
	assert_almost_eq(wired[AttackRecord.KEY_HIT_AMOUNT][0], 0.0, 0.0001, "the record carries the 0")

	# The peer's defender has no resistance — the record, not its board, decides.
	var peer_node: SkillNode = await _peer_node(0.0)
	OutcomeApplier.apply(AttackRecord.rebuild(wired, _peer_graph_of(peer_node)), CombatWorld.live())
	assert_eq(peer_node.get_combat().get_statuses().size(), 0, "the recorded 0 lands nothing")


func _peer_graph_of(node: SkillNode) -> Graph:
	return node.get_parent().get_parent() as Graph


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


## [member StatusInstance.paired] is the one rider gate (ADR 0044): a status
## whose primary hit did not land is a power-0 dud, flagged gated.
func test_a_status_whose_paired_hit_was_gated_lands_as_a_dud() -> void:
	var primary := DamageInstance.new()
	primary.gated = true
	var hit := _status_hit(2.0)
	hit.paired = primary
	hit.land_on(_node.get_combat(), CombatWorld.live())
	assert_true(hit.gated, "a dud is flagged gated")
	assert_almost_eq(hit.power, 0.0, 0.0001, "a dud carries power 0")
	assert_almost_eq(hit.effective_amount, 0.0, 0.0001)
	assert_almost_eq(_node.get_combat().get_status_power(&"test_status"), 0.0, 0.0001,
		"a dud applies nothing")


func test_a_status_with_no_paired_hit_lands_normally() -> void:
	var hit := _status_hit(2.0)
	hit.paired = null
	hit.land_on(_node.get_combat(), CombatWorld.live())
	assert_false(hit.gated)
	assert_almost_eq(_node.get_combat().get_status_power(&"test_status"), 2.0, 0.0001)
