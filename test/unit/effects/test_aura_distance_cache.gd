extends GutTest

## #626: cache aura hop-distance walks per (mirror, source), skip Euclidean
## recomputation on plain alloc/dealloc, and never let a bound-dependent
## DistanceScale skip a rescale it actually needs. See
## effects/aura_distance_cache.gd (the cache), effects/metric/hop_metric.gd +
## effects/metric/euclidean_metric.gd (the "does this dirty me" contract), and
## effects/aura_effect.gd (the dispatch that ties them together).
##
## Same fixture conventions as test/unit/test_aura_effect.gd (chain of nodes,
## real force_allocate/force_deallocate/move_core so the entity's navigator
## mirror is genuinely populated) — a straight 8-node line here instead of two
## disjoint 3-node lines, since several tests below need real hop room.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _nodes: Array[SkillNode]


func before_each() -> void:
	AuraDistanceCache.clear()
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_nodes = []
	for i in 8:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		sn.position = Vector2(i * 100.0, 0.0)
		_graph.add_skill_node(sn)
		_nodes.append(sn)

	# One straight line: 0-1-2-3-4-5-6-7.
	for i in range(7):
		_graph.add_edge(_nodes[i], _nodes[i + 1])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)


func after_each() -> void:
	AuraDistanceCache.clear()


func _spawn(core: SkillNode, owned: Array[SkillNode]) -> Entity:
	var ent := autofree(Entity.new()) as Entity
	ent.display_name = "E"
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(ent)
	await get_tree().process_frame
	for n in owned:
		_alloc.force_allocate(ent, n)
	ent.core_location = core
	ent.stat_board.armor.base_value = 0.0
	return ent


func _armor(n: SkillNode) -> float:
	return float(n.get_local_value(&"armor"))


func _armor_mod(value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = &"armor"
	m.operation = StatModifier.Operation.ADD_BONUS
	m.value = value
	return m


## A second, independent stat for a test's "oracle" or "keystone" aura so it
## can never land on the same board slot as the primary `armor` aura under
## test. `addon_slots` (like `armor`) has `default_value = 0.0` on its
## [StatDef] AND carries no intrinsic STR/DEX/INT/… modifier — unlike
## `spell_damage`/`min_damage_taken`/most of the rest of the board, whose
## nonzero baseline (either an intrinsic contribution, or the [StatDef]'s own
## `default_value`) would confound a bare `get_local_value` read on a node
## that never received a grant at all (`stats_system/defs/*.tres`).
func _oracle_mod(value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = &"addon_slots"
	m.operation = StatModifier.Operation.ADD_BONUS
	m.value = value
	return m


## The handle currently granted to [param node] by [param inst], or null. A
## SAME-object comparison across an event is the strongest available proof
## that a node was never revoked-and-regranted — stronger than reading back
## the applied value, which could coincidentally match after a full rebuild.
func _handle(inst: EffectInstance, node: SkillNode) -> StatModifier:
	var handles := inst.handles_for(node)
	return handles[0] if not handles.is_empty() else null


# ── Acceptance 1: bound-independent scale, alloc/dealloc = membership only ──

func test_euclidean_proportional_scale_untouched_by_unrelated_allocation() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2], _nodes[3]])
	var aura := AuraEffect.new()
	aura.metric = EuclideanMetric.new()
	var scale := ProportionalScale.new()
	scale.per_unit = 0.01
	aura.distance_scale = scale
	aura.modifiers = [_armor_mod(1.0)]
	var inst := ent.grant_effect(aura)

	var before_handle := _handle(inst, _nodes[2])
	assert_not_null(before_handle)
	var before_value := _armor(_nodes[2])

	_alloc.force_allocate(ent, _nodes[4])   # unrelated node, elsewhere on the line

	assert_eq(_handle(inst, _nodes[2]), before_handle,
		"node 2's grant must be the SAME handle — never revoked and regranted by an unrelated allocation")
	assert_almost_eq(_armor(_nodes[2]), before_value, 0.001)
	assert_almost_eq(_armor(_nodes[4]), 400.0 * 0.01, 0.001, "the newly allocated node still gets its own value")

	_alloc.force_deallocate(_nodes[4])
	assert_eq(_handle(inst, _nodes[2]), before_handle, "deallocating elsewhere leaves node 2 untouched too")
	assert_almost_eq(_armor(_nodes[4]), 0.0, 0.001, "deallocated node loses its own grant")


func test_hop_proportional_scale_untouched_beyond_the_diffed_node() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2], _nodes[3]])
	var aura := AuraEffect.new()
	aura.metric = HopMetric.new()
	aura.distance_scale = ProportionalScale.new()   # bound-independent: +1 per hop
	aura.modifiers = [_armor_mod(1.0)]
	var inst := ent.grant_effect(aura)

	var before_handle := _handle(inst, _nodes[1])
	assert_not_null(before_handle)

	_alloc.force_allocate(ent, _nodes[4])   # extends the chain past node 3; node 1's hop count is unaffected

	assert_eq(_handle(inst, _nodes[1]), before_handle,
		"node 1's hop distance from the core never changed — its grant must survive untouched")
	assert_almost_eq(_armor(_nodes[4]), 4.0, 0.001, "new node granted at its own (changed) hop distance")


# ── Acceptance 1b: a bound-dependent scale DOES rescale everyone ───────────

func test_linear_scale_rescales_everyone_when_the_farthest_node_deallocates() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2], _nodes[3]])
	var aura := AuraEffect.new()
	aura.metric = EuclideanMetric.new()
	aura.distance_scale = LinearScale.new()   # normalizes by the widest observed distance
	aura.modifiers = [_armor_mod(10.0)]
	ent.grant_effect(aura)

	# bound = 300 (node 3 is farthest): node 1 at 100/300 -> scale (1 - 1/3).
	assert_almost_eq(_armor(_nodes[1]), 10.0 * (1.0 - 100.0 / 300.0), 0.01)

	_alloc.force_deallocate(_nodes[3])   # the farthest node leaves; bound shrinks to 200

	assert_almost_eq(_armor(_nodes[1]), 10.0 * (1.0 - 100.0 / 200.0), 0.01,
		"the bound moved from 300 to 200 — node 1 must rescale even though its own raw distance never changed")


# ── Acceptance 2: moving the core / a node DOES invalidate Euclidean ───────

func test_moving_core_invalidates_euclidean_distances() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2], _nodes[3]])
	var aura := AuraEffect.new()
	aura.metric = EuclideanMetric.new()
	var scale := ProportionalScale.new()
	scale.per_unit = 1.0
	aura.distance_scale = scale
	aura.modifiers = [_armor_mod(1.0)]
	ent.grant_effect(aura)

	assert_almost_eq(_armor(_nodes[2]), 200.0, 0.01, "200px from core at node 0")

	_alloc.move_core(ent, _nodes[1])

	assert_almost_eq(_armor(_nodes[2]), 100.0, 0.01,
		"core moved to node 1 — Euclidean distance from the NEW source, not a stale value")


## No runtime mechanism moves a SkillNode's position today (procgen/deserialize
## write it once) — so there's no live signal to invalidate off, and adding one
## is explicitly left to a follow-up by #626's own "why a plain per-node signal
## can't drive hop invalidation" section. What this issue's fix must not do is
## cache a Euclidean value across a recompute that happens after a move — and
## it doesn't, because EuclideanMetric is never routed through
## AuraDistanceCache at all (see its `dirties_on_membership_change`).
func test_recompute_after_moving_a_node_reflects_the_new_position() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2]])
	var aura := AuraEffect.new()
	aura.metric = EuclideanMetric.new()
	var scale := ProportionalScale.new()
	scale.per_unit = 1.0
	aura.distance_scale = scale
	aura.modifiers = [_armor_mod(-1.0)]
	var inst := ent.grant_effect(aura)

	assert_almost_eq(_armor(_nodes[1]), -100.0, 0.01)

	_nodes[1].position = Vector2(500.0, 0.0)
	aura.recompute(inst.context)

	assert_almost_eq(_armor(_nodes[1]), -500.0, 0.01,
		"a recompute after the move must read the CURRENT position, not a cached one")


# ── Acceptance 3: two hop auras sharing a source walk once ─────────────────

func test_two_hop_auras_share_one_walk_per_topology_change() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2], _nodes[3]])
	var aura_a := AuraEffect.new()
	aura_a.metric = HopMetric.new()
	aura_a.distance_scale = ProportionalScale.new()   # +1 per hop
	aura_a.modifiers = [_armor_mod(1.0)]

	var aura_b := AuraEffect.new()
	aura_b.metric = HopMetric.new()
	var scale_b := ProportionalScale.new()
	scale_b.per_unit = 2.0                            # +2 per hop
	aura_b.distance_scale = scale_b
	aura_b.modifiers = [_armor_mod(1.0)]

	ent.grant_effect(aura_a)
	ent.grant_effect(aura_b)

	# Node 2: 2 hops -> aura_a +2, aura_b +4 = +6.
	assert_almost_eq(_armor(_nodes[2]), 6.0, 0.001)

	var before := AuraDistanceCache.walk_count
	_alloc.force_allocate(ent, _nodes[4])
	assert_eq(AuraDistanceCache.walk_count - before, 1,
		"one topology change dispatched to two hop-metric auras sharing (mirror, core) must walk once, not twice")

	# Node 4: 4 hops -> aura_a +4, aura_b +8 = +12.
	assert_almost_eq(_armor(_nodes[4]), 12.0, 0.001)


# ── Acceptance 4: parity against a genuine from-scratch recompute ──────────

## Builds a second, never-hooked AuraEffect instance ("oracle") whose
## `recompute` is called by hand after every step — a true full rebuild off
## current world state, wired to its OWN stat id so it can never collide with
## the live, hook-driven aura it's being compared against. If the incremental
## path ever drifts from a from-scratch recompute, this is what catches it.
func _oracle_for(ent: Entity, aura: AuraEffect) -> EffectInstance:
	var inst := EffectInstance.new()
	inst.effect = aura
	inst.context = EffectContext.new(ent.get_combat(), inst)
	return inst


## `addon_slots` (unlike `armor`) carries a per-node intrinsic baseline
## (`skill_node.gd`'s "addon_slots = base(0) + allocation_level"), so an
## absolute read isn't comparable to `armor`'s. Re-baselined every step rather
## than once up front, in case that intrinsic ever moves on its own — revoke
## the oracle's own prior grant first so the snapshot reflects ONLY the
## baseline, then diff [param oracle_inst]'s fresh [method AuraEffect.recompute]
## against it. The result is exactly what the oracle aura itself contributed.
func _snapshot(stat_id: StringName) -> Dictionary:
	var out: Dictionary = {}
	for n in _nodes:
		out[n] = float(n.get_local_value(stat_id))
	return out


func _oracle_recompute_delta(oracle: AuraEffect, oracle_inst: EffectInstance) -> Dictionary:
	oracle_inst.context.revoke_all()
	var before := _snapshot(&"addon_slots")
	oracle.recompute(oracle_inst.context)
	var out: Dictionary = {}
	for n in _nodes:
		out[n] = float(n.get_local_value(&"addon_slots")) - float(before.get(n, 0.0))
	return out


func test_parity_hop_proportional_scale_across_a_sequence_of_events() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2], _nodes[3], _nodes[4]])

	var live := AuraEffect.new()
	live.metric = HopMetric.new()
	live.distance_scale = ProportionalScale.new()
	live.modifiers = [_armor_mod(1.0)]
	ent.grant_effect(live)

	var oracle := AuraEffect.new()
	oracle.metric = HopMetric.new()
	oracle.distance_scale = ProportionalScale.new()
	oracle.modifiers = [_oracle_mod(1.0)]
	var oracle_inst := _oracle_for(ent, oracle)

	var steps: Array[Callable] = [
		func() -> void: _alloc.force_allocate(ent, _nodes[5]),
		func() -> void: _alloc.force_deallocate(_nodes[4]),
		func() -> void: _alloc.move_core(ent, _nodes[1]),
		func() -> void: _alloc.force_allocate(ent, _nodes[4]),
		func() -> void: _alloc.force_deallocate(_nodes[5]),
		func() -> void: _alloc.move_core(ent, _nodes[0]),
	]

	for step in steps:
		step.call()
		var delta := _oracle_recompute_delta(oracle, oracle_inst)
		for n in _nodes:
			assert_almost_eq(_armor(n), float(delta[n]), 0.001,
				"%s: incremental path diverged from a from-scratch recompute" % n.name)


func test_parity_euclidean_proportional_scale_across_a_sequence_of_events() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2], _nodes[3], _nodes[4]])

	var live := AuraEffect.new()
	live.metric = EuclideanMetric.new()
	var live_scale := ProportionalScale.new()
	live_scale.per_unit = 0.01
	live.distance_scale = live_scale
	live.modifiers = [_armor_mod(1.0)]
	ent.grant_effect(live)

	var oracle := AuraEffect.new()
	oracle.metric = EuclideanMetric.new()
	var oracle_scale := ProportionalScale.new()
	oracle_scale.per_unit = 0.01
	oracle.distance_scale = oracle_scale
	oracle.modifiers = [_oracle_mod(1.0)]
	var oracle_inst := _oracle_for(ent, oracle)

	var steps: Array[Callable] = [
		func() -> void: _alloc.force_allocate(ent, _nodes[5]),
		func() -> void: _alloc.force_deallocate(_nodes[4]),
		func() -> void: _alloc.move_core(ent, _nodes[1]),
		func() -> void: _alloc.force_allocate(ent, _nodes[4]),
		func() -> void: _alloc.force_deallocate(_nodes[5]),
		func() -> void: _alloc.move_core(ent, _nodes[0]),
	]

	for step in steps:
		step.call()
		var delta := _oracle_recompute_delta(oracle, oracle_inst)
		for n in _nodes:
			assert_almost_eq(_armor(n), float(delta[n]), 0.001,
				"%s: incremental path diverged from a from-scratch recompute" % n.name)


# ── Acceptance 5: a change outside reach must not dirty the aura ───────────

func test_node_outside_bounded_euclidean_reach_does_not_dirty_the_aura() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2], _nodes[3], _nodes[4], _nodes[5]])
	var finder := EuclideanRangeFinder.new()
	finder.max_distance = 250.0   # nodes 0-2 (0/100/200px) in range; node 5 (500px) is not
	var aura := AuraEffect.new()
	aura.reach = finder
	aura.metric = HopMetric.new()
	aura.distance_scale = ProportionalScale.new()
	aura.modifiers = [_armor_mod(1.0)]
	var inst := ent.grant_effect(aura)

	var before_handle := _handle(inst, _nodes[1])
	assert_not_null(before_handle)

	_alloc.force_deallocate(_nodes[5])   # outside reach entirely — must not touch the aura

	assert_eq(_handle(inst, _nodes[1]), before_handle,
		"a change to a node outside reach must not touch an in-reach node's grant")


# ── Acceptance 6: a node that becomes unreachable loses its buff ───────────

func test_node_that_becomes_unreachable_loses_its_hop_buff() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2]])
	var aura := AuraEffect.new()
	aura.metric = HopMetric.new()
	aura.distance_scale = FlatScale.new()
	aura.modifiers = [_armor_mod(5.0)]
	ent.grant_effect(aura)

	assert_almost_eq(_armor(_nodes[2]), 5.0, 0.001)

	_alloc.force_deallocate(_nodes[1])   # cuts node 2 off from the core

	assert_almost_eq(_armor(_nodes[2]), 0.0, 0.001,
		"node 2 is unreachable now — absent from the new hop map must revoke, not leave a stale grant")


# ── Acceptance 7: keystone + core aura keep separate distance maps ─────────

## The granted handle's OWN `.value` — the exact post-[method
## DistanceScale.scale] magnitude [method EffectContext.grant_scaled] wrote —
## rather than `get_local_value`, which folds in whatever intrinsic baseline
## the target stat already carries (see `_snapshot`'s doc comment). Reading
## the handle sidesteps that confound entirely: 0.0 for "nothing granted"
## either way, so a not-granted node and a granted-zero node read the same.
func _granted_value(inst: EffectInstance, node: SkillNode) -> float:
	var h := _handle(inst, node)
	return h.value if h != null else 0.0


func test_keystone_and_core_aura_keep_separate_distance_maps() -> void:
	var ent: Entity = await _spawn(_nodes[0], [_nodes[0], _nodes[1], _nodes[2], _nodes[3], _nodes[4]])

	var core_aura := AuraEffect.new()
	core_aura.metric = HopMetric.new()
	core_aura.distance_scale = FlatScale.new()
	core_aura.modifiers = [_armor_mod(1.0)]
	ent.grant_effect(core_aura)   # source = core (node 0)

	var keystone_aura := AuraEffect.new()
	keystone_aura.metric = HopMetric.new()
	keystone_aura.distance_scale = FlatScale.new()
	keystone_aura.modifiers = [_oracle_mod(1.0)]
	var keystone_inst := ent.grant_effect(keystone_aura, _nodes[4])   # source = node 4, a keystone carrier

	for n in [_nodes[0], _nodes[1], _nodes[2], _nodes[3], _nodes[4]]:
		assert_almost_eq(_armor(n), 1.0, 0.001, "%s: core aura" % n.name)
		assert_almost_eq(_granted_value(keystone_inst, n), 1.0, 0.001, "%s: keystone aura" % n.name)

	var before := AuraDistanceCache.walk_count
	_alloc.force_allocate(ent, _nodes[5])
	assert_eq(AuraDistanceCache.walk_count - before, 2,
		"core aura and keystone aura radiate from different sources — separate cache entries, separate walks")

	assert_almost_eq(_armor(_nodes[5]), 1.0, 0.001, "core aura reaches the new node too")
	assert_almost_eq(_granted_value(keystone_inst, _nodes[5]), 1.0, 0.001, "so does the keystone aura")
