extends GutTest

## AuraEffect.recompute() batching (#627). A core move revokes every node's OLD
## grant then re-grants the NEW one — same stat, written twice — and unbatched
## that is two immediate `value_changed` emissions where one would do.
## `recompute()` now brackets each node board it touches in `begin_batch` /
## `end_batch` so the revoke+grant burst settles once per stat that actually
## moved.
##
## Scope note (settled with the orchestrator before writing this file): the
## issue's own "~150, not ~1,200" target assumed `end_batch` emits once per
## BOARD. It emits once per STAT THAT MOVED (`stats_system/stat_board.gd:451`),
## and the real Serpent aura (`entity/core/serpent_core.tres`) moves 4 distinct
## stats per node (armor, blade_damage, spell_damage, ranged_damage) — the same
## 4 ids on BOTH of its two aura resources, each an independently-dispatched
## `EffectInstance` with no shared batch between them (`Entity.dispatch`,
## outside this issue's owned files). So the reachable-by-batching-alone target
## is a 2x-per-aura collapse (revoke+grant of the same stat -> 1 settle), not a
## 1-per-board settle. Asserted directly below against the real Serpent shape.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

## The 4 stat ids `serpent_core.tres`'s two auras both target — 1 plain
## modifier (armor) + 1 composite of the other 3, per aura.
const _SERPENT_STAT_IDS: Array[StringName] = [&"armor", &"blade_damage", &"spell_damage", &"ranged_damage"]

var _graph: Graph
var _alloc: AllocationSystem
var _nodes: Array[SkillNode]


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	# A straight 6-node chain: 0-1-2-3-4-5. Long enough to have a real
	# "interior" (nodes both revoked from and re-granted to) either side of
	# the two ends the core visits.
	_nodes = []
	for i in 6:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		sn.position = Vector2(i * 100.0, 0.0)
		_graph.add_skill_node(sn)
		_nodes.append(sn)
	for i in 5:
		_graph.add_edge(_nodes[i], _nodes[i + 1])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)


func _spawn(core: SkillNode, owned: Array[SkillNode]) -> Entity:
	var ent := autofree(Entity.new()) as Entity
	ent.display_name = "E"
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(ent)
	await get_tree().process_frame
	for n in owned:
		_alloc.force_allocate(ent, n)
	ent.core_location = core
	return ent


func _mod(stat_id: StringName, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.ADD_BONUS
	m.value = value
	return m


## Mirrors `entity/core/serpent_core.tres`'s shape exactly: 1 plain armor
## modifier + 1 composite of the other 3, per aura, same 4 stat ids on both.
func _serpent_hop_buff() -> AuraEffect:
	var aura := AuraEffect.new()
	aura.metric = HopMetric.new()
	aura.distance_scale = ProportionalScale.new()   # +1 per hop; 0 at the source
	var composite := CompositeStatModifier.new()
	composite.children = [_mod(&"blade_damage", 0.5), _mod(&"spell_damage", 0.5), _mod(&"ranged_damage", 0.5)]
	aura.modifiers = [_mod(&"armor", 1.0), composite]
	return aura


func _serpent_euclid_penalty() -> AuraEffect:
	var aura := AuraEffect.new()
	aura.metric = EuclideanMetric.new()
	var scale := ProportionalScale.new()
	scale.per_unit = 0.005
	aura.distance_scale = scale
	var composite := CompositeStatModifier.new()
	composite.children = [_mod(&"blade_damage", -0.5), _mod(&"spell_damage", -0.5), _mod(&"ranged_damage", -0.5)]
	aura.modifiers = [_mod(&"armor", -1.0), composite]
	return aura


# ── Acceptance 1/8 (corrected): the mechanism — revoke+grant of the same
# stat within one recompute settles once, not twice ─────────────────────────

func test_core_move_collapses_revoke_and_grant_of_the_same_stat_into_one_settle() -> void:
	var ent: Entity = await _spawn(_nodes[0], _nodes)
	ent.grant_effect(_serpent_hop_buff())

	# Node 3 stays in reach (nonzero hop distance) both before and after the
	# move — its `armor` modifier gets revoked (old distance) then re-granted
	# (new distance) within the SAME recompute call.
	var armor := _nodes[3]._ensure_local_stat(&"armor")
	var before := float(armor.get_value())
	var seen: Array[int] = []
	armor.value_changed.connect(func() -> void: seen.append(1))

	ent.core_location = _nodes[5]   # direct assignment: move_core requires adjacency, this doesn't

	assert_eq(seen.size(), 1,
		"revoke (old hop distance) + grant (new hop distance) to the same stat must settle once")
	assert_ne(float(armor.get_value()), before, "the value itself must still have moved")
	# node 3 is 2 hops from the new core (node 5), was 3 from the old (node 0).
	assert_almost_eq(float(armor.get_value()), 2.0, 0.001)


## The guard that matters most: batching defers notification, never value.
## `Stat.get_value()` recomputes from bins per call, so the post-recompute
## read is exact — same as an unbatched rebuild would have landed on.
func test_final_values_match_hand_computed_expectation_after_a_core_move() -> void:
	var ent: Entity = await _spawn(_nodes[0], _nodes)
	ent.grant_effect(_serpent_hop_buff())
	ent.grant_effect(_serpent_euclid_penalty())

	ent.core_location = _nodes[2]

	for i in 6:
		var hop_dist := absi(i - 2)
		var euclid_dist := absf((i - 2) * 100.0)
		var expected := float(hop_dist) * 1.0 + euclid_dist * -0.005
		assert_almost_eq(float(_nodes[i].get_local_value(&"armor")), expected, 0.001,
			"node %d armor after core move to node 2" % i)


# ── Acceptance 2 (corrected numbers): measured emission counts ─────────────

## The real Serpent shape: 2 auras, each independently dispatched, each
## touching the same 4 stat ids. Batching is scoped per `recompute()` call
## (per aura), not shared across the two — settled with the orchestrator as
## out of this issue's owned files (`Entity.dispatch()`). So each aura's own
## revoke+grant burst collapses (4 stats moved -> 4 settles), and the two
## auras' settles don't merge: 8 settles per touched node board, not 1.
##
## Every one of the 6 chain nodes ends up touched by the move (old core loses
## its grants, new core gains them, the rest get revoke+grant) — so the
## measured total is exactly 8 * 6 = 48. Unbatched (master) would have been
## 16 per interior node (4 stats x 2 ops x 2 auras) and 8 at each end (one op
## only there) = 4*16 + 2*8 = 80. Both numbers reported to the orchestrator
## for the issue's corrected acceptance text.
##
## [b]Re-pointed 48 -> 24 by #647.[/b] The paragraph above is the record of what
## #627 could reach with a per-`recompute` batch; the "not shared across the two
## auras" clause it rests on is exactly what #647 removed. `Entity.dispatch` now
## holds each touched board open for the whole hook dispatch, so the second
## aura's writes join the first aura's batch and the pair settles ONCE per stat:
## 4 stats x 6 nodes = 24. This is the ONLY assertion in this file #647 moved —
## every value assertion above and below is untouched, because batching defers
## notification, never value.
func test_core_move_on_the_real_serpent_shape_settles_24_times_not_48_or_80() -> void:
	var ent: Entity = await _spawn(_nodes[0], _nodes)
	ent.grant_effect(_serpent_hop_buff())
	ent.grant_effect(_serpent_euclid_penalty())

	var seen: Array[int] = []
	for n in _nodes:
		for id in _SERPENT_STAT_IDS:
			var s: Stat = n._ensure_local_stat(id)
			s.value_changed.connect(func() -> void: seen.append(1))

	ent.core_location = _nodes[5]

	assert_eq(seen.size(), 24,
		"6 nodes x 4 stats — revoke+grant AND both auras collapsed into one dispatch-scoped batch (#647)")


# ── Acceptance 3/9 (corrected numbering: originally 3, then restated as 9
# for the core-move path specifically) — guaranteed close ──────────────────

## `modifiers.is_empty()` early return. Old grants exist (from a prior
## recompute with real modifiers); clearing the array and forcing another
## recompute must still close every batch it opened for the revoke.
func test_no_board_left_batching_when_modifiers_go_empty_mid_recompute() -> void:
	var ent: Entity = await _spawn(_nodes[0], _nodes)
	var aura := _serpent_hop_buff()
	ent.grant_effect(aura)
	assert_gt(float(_nodes[3].get_local_value(&"armor")), 0.0, "sanity: granted before the empty-out")

	aura.modifiers = []
	ent.core_location = _nodes[2]   # re-triggers _on_core_moved -> recompute()

	for n in _nodes:
		assert_false(n.node_board.is_batching(),
			"node %s's board must not be left batching after an empty-modifiers early return" % n.name)
	# And a board left batching would silently eat this — prove it doesn't.
	var armor := _nodes[3]._ensure_local_stat(&"armor")
	var seen: Array[int] = []
	armor.value_changed.connect(func() -> void: seen.append(1))
	armor.base_value += 1.0
	assert_eq(seen.size(), 1, "an unmatched begin_batch would have swallowed this notification forever")


## `source == null` early return (entity-wide aura, no source_node, and
## core_location cleared to null). Old grants must still be revoked and every
## opened batch still closed.
func test_no_board_left_batching_when_source_and_core_location_are_both_null() -> void:
	var ent: Entity = await _spawn(_nodes[0], _nodes)
	ent.grant_effect(_serpent_hop_buff())
	assert_gt(float(_nodes[3].get_local_value(&"armor")), 0.0, "sanity: granted before clearing core_location")

	ent.core_location = null   # source_node is null too (core-class aura) -> hits the source==null guard

	for n in _nodes:
		assert_false(n.node_board.is_batching(),
			"node %s's board must not be left batching after the source==null early return" % n.name)
	assert_almost_eq(float(_nodes[3].get_local_value(&"armor")), 0.0, 0.001,
		"the early return still ran after revoke_all — old grants are gone")


# ── Acceptance 4: a node lost mid-cascade leaves no stale bound row
# (existing behaviour, unaffected by batching) ───────────────────────────────

## `AllocationSystem`'s cascades clear ownership rather than free the
## `SkillNode` object (it never calls `queue_free`/`free` on a dealloc — only
## `Graph.remove_skill_node`, an editor/procgen-only operation, does that
## deferredly). The realistic "mid-cascade" case `recompute()` must survive is
## a node dropping out of the owned mirror partway through — exercised here via
## `force_deallocate`, the same primitive `test_aura_effect.gd`'s own
## `test_allocating_a_node_in_reach_buffs_it` uses.
func test_a_node_deallocated_mid_cascade_leaves_no_stale_row_and_no_stuck_batch() -> void:
	var ent: Entity = await _spawn(_nodes[0], _nodes)
	ent.grant_effect(_serpent_hop_buff())
	assert_gt(float(_nodes[5].get_local_value(&"armor")), 0.0, "sanity: granted before the dealloc")

	_alloc.force_deallocate(_nodes[5])   # drops out of the owned mirror mid-recompute's next trigger
	ent.core_location = _nodes[3]        # recompute must skip the now-unowned node cleanly

	for n in _nodes:
		if n.owned_by == ent:
			assert_false(n.node_board.is_batching(),
				"node %s's board must not be left batching after a recompute that skipped an unowned node" % n.name)
	assert_almost_eq(float(_nodes[3].get_local_value(&"armor")), 0.0, 0.001, "new core: untouched")
	assert_almost_eq(float(_nodes[0].get_local_value(&"armor")), 3.0, 0.001, "3 hops from the new core")
	assert_almost_eq(float(_nodes[5].get_local_value(&"armor")), 0.0, 0.001,
		"deallocated: no stale bound row left granting it armor")
