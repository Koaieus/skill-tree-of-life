extends GutTest

## The dispatch-scoped batch ledger (#647) — `EntityCombat.begin_dispatch` /
## `hold_batch` / `end_dispatch`, entered from `Entity.dispatch`.
##
## #627 batched inside one `AuraEffect.recompute()`, so the Serpent's TWO auras
## each settled the same 4 stats on the same node board: 48 settles on a 6-node
## chain. This holds each touched board open for the whole hook dispatch, so the
## second aura joins the first's batch — 24.
##
## What this file guards is not the number (that lives next door in
## `test_aura_batch_notify.gd`), it is the ledger's four hazards:
##
## - **The drain is unconditional.** GDScript has no `finally`, and a stranded
##   `begin_batch` swallows every later notification on that board *forever* —
##   presenting as stats that stop updating, not as a crash. Re-entrant grants,
##   re-entrant revokes and nested dispatches all have to come out clean.
## - **Nested dispatches must not double-close** — only the outermost drains.
## - **A no-op dispatch opens zero batches.** This is the whole difference
##   between the ledger and the "pre-bracket every owned node's board" shape #647
##   explicitly rejected (`2 * owned` begin/end calls per dispatch, 300 on a
##   150-node Serpent, paid even when nothing touches a node board).
## - **Two entities may hold the same board.** A GLOBAL-scope aura reaches nodes
##   somebody else owns, so entity A's ledger can hold node N's board open while
##   B's dispatch also batches it. `begin_batch` is a plain depth counter, so
##   this nests — but it settles at the OUTERMOST close, which is the
##   non-obvious property.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

## The 4 stat ids `entity/core/serpent_core.tres`'s two auras both target.
const _SERPENT_STAT_IDS: Array[StringName] = [&"armor", &"blade_damage", &"spell_damage", &"ranged_damage"]

var _graph: Graph
var _alloc: AllocationSystem
var _nodes: Array[SkillNode]


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)
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


## A flat, whole-subgraph aura — one stat, one modifier. Enough to touch every
## owned node's board without the Serpent's composite noise.
func _flat_aura(value: float = 1.0, aura_scope: AuraEffect.Scope = AuraEffect.Scope.OWNED) -> AuraEffect:
	var aura := AuraEffect.new()
	aura.metric = HopMetric.new()
	aura.distance_scale = ProportionalScale.new()
	aura.scope = aura_scope
	aura.modifiers = [_mod(&"armor", value)]
	return aura


## `serpent_core.tres`'s shape: 1 plain armor modifier + 1 composite of the
## other 3, per aura, the same 4 stat ids on both. Mirrors
## `test_aura_batch_notify.gd`'s fixture so the two files' numbers compare.
func _serpent_hop_buff() -> AuraEffect:
	var aura := AuraEffect.new()
	aura.metric = HopMetric.new()
	aura.distance_scale = ProportionalScale.new()
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


func _assert_no_board_left_batching(where: String) -> void:
	for n in _nodes:
		if n.node_board != null:
			assert_false(n.node_board.is_batching(),
				"%s: node %s's board must not be left batching" % [where, n.name])


# ── D4: the drain is unconditional ─────────────────────────────────────────

## A hook that revokes another effect re-entrantly mid-dispatch. `dispatch()`
## iterates `bucket.duplicate()` precisely so this is legal, and the revoked
## effect's own `_on_revoked` reaches back into `revoke_all` — writing to boards
## the ledger is holding open.
func test_a_hook_that_revokes_re_entrantly_leaves_no_board_batching() -> void:
	var ent: Entity = await _spawn(_nodes[0], _nodes)
	var victim := ent.grant_effect(_flat_aura(1.0))
	var saboteur := ReEntrantRevokeEffect.new()
	saboteur.victim = victim
	ent.grant_effect(saboteur)

	ent.core_location = _nodes[5]   # dispatches _on_core_moved to both

	assert_true(saboteur.fired, "sanity: the saboteur hook actually ran")
	_assert_no_board_left_batching("after a re-entrant revoke")
	assert_eq(ent.get_combat().held_batch_count(), 0, "the ledger drained")
	# The revoked aura's grants are gone — the revoke really did land.
	assert_almost_eq(float(_nodes[0].get_local_value(&"armor")), 0.0, 0.001)


## A hook that grants a fresh effect mid-dispatch. `grant_effect` runs
## `_on_granted` -> `recompute()` immediately, INSIDE the outer dispatch, so the
## new aura's boards join the ledger the outer drain owns.
func test_a_hook_that_grants_re_entrantly_leaves_no_board_batching_and_still_applies() -> void:
	var ent: Entity = await _spawn(_nodes[0], _nodes)
	var granter := ReEntrantGrantEffect.new()
	granter.to_grant = _flat_aura(1.0)
	ent.grant_effect(granter)

	ent.core_location = _nodes[5]

	assert_true(granter.fired, "sanity: the granting hook actually ran")
	_assert_no_board_left_batching("after a re-entrant grant")
	assert_eq(ent.get_combat().held_batch_count(), 0, "the ledger drained")
	# Value parity: node 0 is 5 hops from the new core, +1 armor per hop.
	assert_almost_eq(float(_nodes[0].get_local_value(&"armor")), 5.0, 0.001,
		"the re-entrantly granted aura applied in full — batching defers notification, never value")


## The hazard made visible: a board left batching swallows every subsequent
## notification on it, silently and forever. If the drain ever regresses, this
## is the assertion that says so in one line.
func test_a_notification_after_a_re_entrant_dispatch_still_arrives() -> void:
	var ent: Entity = await _spawn(_nodes[0], _nodes)
	ent.grant_effect(_flat_aura(1.0))
	var nester := NestedDispatchEffect.new()
	ent.grant_effect(nester)

	ent.core_location = _nodes[5]
	assert_true(nester.fired, "sanity: the nesting hook actually ran")

	var armor := _nodes[3]._ensure_local_stat(&"armor")
	var seen := [0]   # an Array, not a local: a lambda captures locals BY VALUE
	armor.value_changed.connect(func() -> void: seen[0] += 1)
	armor.base_value += 1.0

	assert_eq(seen[0], 1, "an unmatched begin_batch would have eaten this forever")


# ── D5: nested dispatches drain once, at the outermost ─────────────────────

## The inner dispatch must NOT close boards the outer one is still filling —
## that would both defeat the merge and unbalance `end_batch`. The depth counter
## is what makes it correct; this asserts the observable consequence.
func test_a_nested_dispatch_does_not_drain_the_outer_ledger() -> void:
	var ent: Entity = await _spawn(_nodes[0], _nodes)
	ent.grant_effect(_flat_aura(1.0))
	var nester := NestedDispatchEffect.new()
	ent.grant_effect(nester)

	ent.core_location = _nodes[5]

	assert_gt(nester.held_inside_inner, 0,
		"the inner dispatch must still SEE the outer ledger's held boards, not a drained one")
	assert_eq(ent.get_combat().held_batch_count(), 0, "and the outer drain still ran")
	_assert_no_board_left_batching("after a nested dispatch")


# ── D2 vs the rejected D1 shape: a no-op dispatch opens zero batches ────────

## The single assertion that keeps a later refactor from quietly regressing to
## "pre-bracket every owned node's board". An effect whose hook touches no node
## board must leave the ledger empty while it runs.
func test_a_dispatch_whose_hooks_touch_no_node_board_opens_zero_batches() -> void:
	var ent: Entity = await _spawn(_nodes[0], _nodes)
	var probe := LedgerProbeEffect.new()
	ent.grant_effect(probe)   # no aura granted: nothing touches a node board

	ent.core_location = _nodes[5]

	assert_true(probe.fired, "sanity: the probe hook actually ran")
	assert_eq(probe.held_during_hook, 0,
		"a dispatch that touches no node board must open no batches at all")


## And the positive control on the same probe: with an aura present, the ledger
## is non-empty by the time a later effect's hook runs — proving the assertion
## above measures something real rather than an always-zero counter.
func test_the_same_probe_sees_a_non_empty_ledger_once_an_aura_is_present() -> void:
	var ent: Entity = await _spawn(_nodes[0], _nodes)
	ent.grant_effect(_flat_aura(1.0))   # granted FIRST, so it dispatches first
	var probe := LedgerProbeEffect.new()
	ent.grant_effect(probe)

	ent.core_location = _nodes[5]

	assert_eq(probe.held_during_hook, _nodes.size(),
		"the aura's 6 node boards are held open when the next effect's hook runs")


# ── Two entities holding the same board ────────────────────────────────────

## `AllocationSystem`'s forced-dealloc cascade and `SkillNode._on_damaged` both
## dispatch on whichever entity owns the node, so two entities' ledgers can hold
## the same node board at once. A GLOBAL-scope aura is the reproducible version:
## it reaches nodes the other entity owns. `begin_batch` is a plain depth
## counter, so this nests — and settles at the OUTERMOST close.
func test_two_entities_holding_the_same_node_board_settle_once_at_the_outer_close() -> void:
	var a_nodes: Array[SkillNode] = [_nodes[0], _nodes[1], _nodes[2]]
	var b_nodes: Array[SkillNode] = [_nodes[3], _nodes[4], _nodes[5]]
	var ent_a: Entity = await _spawn(_nodes[0], a_nodes)
	var ent_b: Entity = await _spawn(_nodes[3], b_nodes)
	ent_a.display_name = "A"
	ent_b.display_name = "B"

	ent_a.grant_effect(_flat_aura(1.0, AuraEffect.Scope.GLOBAL))
	ent_b.grant_effect(_flat_aura(10.0, AuraEffect.Scope.GLOBAL))

	# A's hook fires B's dispatch from INSIDE A's own — the interleave.
	var crosser := CrossEntityDispatchEffect.new()
	crosser.other = ent_b
	ent_a.grant_effect(crosser)

	var shared := _nodes[5]._ensure_local_stat(&"armor")
	var seen := [0]
	shared.value_changed.connect(func() -> void: seen[0] += 1)

	ent_a.core_location = _nodes[2]

	assert_true(crosser.fired, "sanity: the cross-entity hook actually ran")
	_assert_no_board_left_batching("after an interleaved cross-entity dispatch")
	assert_eq(ent_a.get_combat().held_batch_count(), 0, "A's ledger drained")
	assert_eq(ent_b.get_combat().held_batch_count(), 0, "B's ledger drained")
	assert_eq(seen[0], 1,
		"both entities rewrote node 5's armor, and it settled once — at A's outermost close")


# ── Test-local effects ─────────────────────────────────────────────────────

class ReEntrantRevokeEffect extends Effect:
	var victim: EffectInstance
	var fired: bool = false

	func _on_core_moved(ctx: EffectContext, _from: SkillNode, _to: SkillNode) -> void:
		fired = true
		if victim != null and ctx.entity != null:
			ctx.entity.revoke_effect(victim)
			victim = null


class ReEntrantGrantEffect extends Effect:
	var to_grant: Effect
	var fired: bool = false

	func _on_core_moved(ctx: EffectContext, _from: SkillNode, _to: SkillNode) -> void:
		fired = true
		if to_grant != null and ctx.entity != null:
			var g := to_grant
			to_grant = null   # once, not on every subsequent move
			ctx.entity.grant_effect(g)


## Re-enters `Entity.dispatch` on a DIFFERENT hook from inside the current one,
## and records what the ledger looked like while the inner scope was live.
class NestedDispatchEffect extends Effect:
	var fired: bool = false
	var held_inside_inner: int = -1
	var _inner: InnerProbe

	func _on_core_moved(ctx: EffectContext, _from: SkillNode, _to: SkillNode) -> void:
		if fired:
			return
		fired = true
		var ent := ctx.entity
		if ent == null:
			return
		_inner = InnerProbe.new()
		ent.grant_effect(_inner)
		ent.dispatch(&"_on_turn_start")
		held_inside_inner = _inner.held

	class InnerProbe extends Effect:
		var held: int = -1

		func _on_turn_start(ctx: EffectContext) -> void:
			held = ctx.combat.held_batch_count()


## Reads the ledger depth from inside a hook — the no-op acceptance probe.
class LedgerProbeEffect extends Effect:
	var fired: bool = false
	var held_during_hook: int = -1

	func _on_core_moved(ctx: EffectContext, _from: SkillNode, _to: SkillNode) -> void:
		fired = true
		held_during_hook = ctx.combat.held_batch_count()


## Fires ANOTHER entity's dispatch from inside this one's — the interleave that
## puts two ledgers on one node board.
class CrossEntityDispatchEffect extends Effect:
	var other: Entity
	var fired: bool = false

	func _on_core_moved(ctx: EffectContext, _from: SkillNode, _to: SkillNode) -> void:
		if fired or other == null:
			return
		fired = true
		other.dispatch(&"_on_core_moved", [other.core_location, other.core_location])


# ── Acceptance: the second measurement, at #620's REAL shape ───────────────

## #647's own fixture is 6 owned nodes; #620's Serpent is ~150, and the issue
## names that second number as the one deciding whether this is worth keeping.
## Same two-aura Serpent shape, one core move end to end:
##
## | owned nodes | #627 (per-recompute batch) | #647 (per-dispatch batch) |
## |-------------|----------------------------|---------------------------|
## | 6           | 48                         | 24                        |
## | 150         | 1200                       | 600                       |
##
## Both "before" columns measured on this branch by making `hold_batch()` return
## `false` unconditionally (a one-line revert to #627 behaviour) and re-running.
## The 2x holds at scale — it is one settle per stat that moved, per node, with
## the second aura merged into the first's batch, so it stays 2x for any number
## of auras beyond one.
func test_the_two_x_holds_at_the_real_150_node_serpent_shape() -> void:
	var big: Array[SkillNode] = []
	for i in 150:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "B%d" % i
		sn.position = Vector2(i * 100.0, 500.0)
		_graph.add_skill_node(sn)
		big.append(sn)
	for i in 149:
		_graph.add_edge(big[i], big[i + 1])

	var ent: Entity = await _spawn(big[0], big)
	ent.grant_effect(_serpent_hop_buff())
	ent.grant_effect(_serpent_euclid_penalty())

	var seen := [0]
	for n in big:
		for id in _SERPENT_STAT_IDS:
			n._ensure_local_stat(id).value_changed.connect(func() -> void: seen[0] += 1)

	ent.core_location = big[149]

	assert_eq(seen[0], 600,
		"150 nodes x 4 stats, both auras merged into one dispatch-scoped batch per board")
	_assert_no_board_left_batching("after the 150-node core move")
