extends GutTest

## #795 — characterization test for BladePopResolver's reachability BFS and
## kill cascade, written against the CURRENT (pre-refactor) O(V x E) rescan
## implementation and left unmodified across the refactor. If this file needed
## to change to stay green, the refactor changed behaviour, not just
## complexity — see .claude/rules/testing.md and the #795 issue.
##
## Graph: a spine (0-1-2-3-4), a branch off 2 (2-5-6), and a SECOND path from
## 2 to 4 via 7-8-9 (2-7-8-9-4) that, together with the spine's 2-3-4, forms a
## genuine cycle. Deliberately not a tree, so a wrong adjacency map (an edge
## only recorded in one direction, or a vertex's second incident edge
## dropped) is actually observable:
##
##   - vertex 3 sits ON the cycle but is otherwise redundant — removing it
##     alone leaves 4/7/8/9 reachable via the 2-7-8-9-4 detour. A one-directional
##     adjacency bug (only registering (2,3) under vertex 2, say, and not also
##     under vertex 3, or vice versa) would get this wrong.
##   - vertex 2 is the actual cut vertex for everything past it — both the
##     branch (5-6) AND the cycle (3-4-7-8-9) hang off it alone, since both of
##     the cycle's entry edges (2,3) and (2,7) are incident to 2.
##
##    0 - 1 - 2 --- 3
##            |\      \
##            5 7      4
##            |  \    /
##            6   8 - 9
##
## (2 has edges to 1, 3, 5, 7; 4 has edges to 3 and 9.) ~10 vertices.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SPIKE_SCENE := preload("res://skill_node/addons/spike_ring_addon.tscn")

const _SPIKE_POWER := 5.0


func _spawn_node(graph: Node, nm: String) -> SkillNode:
    var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
    node.name = nm
    graph.skill_nodes_container.add_child(node)
    return node


func _make_entity(graph: Node) -> Entity:
    var board: EntityStatBoard = _BOARD.duplicate(true)
    var entity: Entity = autofree(Entity.new())
    entity.stat_board = board
    graph.add_child(entity)
    return entity


## Attacker owns nothing here that the resolver reads; defender owns one
## spiked node used as the pop target for both kills in the cascade test
## (spikes are persistent — popping doesn't consume them, see
## test_spike_pop.gd's test_persistent_pops_every_call).
func _setup() -> Dictionary:
    var graph := _GRAPH_SCENE.instantiate()
    add_child_autofree(graph)
    var attacker := _make_entity(graph)
    var defender := _make_entity(graph)

    var spike_node := _spawn_node(graph, "Spiked")
    await get_tree().process_frame

    var alloc := AllocationSystem.new()
    alloc.graph = graph
    add_child_autofree(alloc)
    alloc.force_allocate(defender, spike_node)

    var spike := _SPIKE_SCENE.instantiate() as SpikeRingAddon
    var mod := StatModifier.new()
    mod.stat_id = &"blade_damage"
    mod.operation = StatModifier.Operation.ADD_BONUS
    mod.value = _SPIKE_POWER
    spike.local_modifiers = [mod]
    spike_node.add_child(spike)

    return {"graph": graph, "attacker": attacker, "defender": defender, "spike_node": spike_node}


## The branchy-cycle blade described in the file header. Positions are
## arbitrary and distinct; only `edges` and `pivot_index` matter to the BFS.
func _branchy_cycle_state() -> BladeState:
    var positions: Array[Vector2] = []
    var radii: Array[float] = []
    for i in range(10):
        positions.append(Vector2(float(i) * 40.0, 0.0))
        radii.append(16.0)
    var edges: Array[Vector2i] = [
        Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 4),
        Vector2i(2, 5), Vector2i(5, 6),
        Vector2i(2, 7), Vector2i(7, 8), Vector2i(8, 9), Vector2i(9, 4),
    ]
    return BladeState.build(positions, 0, edges, radii)


func _ev(t: float, particle_idx: int, target: SkillNode) -> BladeHitEvent:
    return BladeHitEvent.new(t, particle_idx, -1, target)


func _sorted_keys(d: Dictionary) -> Array:
    var keys := d.keys()
    keys.sort()
    return keys


# ── _reachable_from_pivot: exact reachable set, pinned directly ──────────────

func test_reachable_from_pivot_nothing_removed_reaches_everyone() -> void:
    var state := _branchy_cycle_state()
    var reach := BladePopResolver._reachable_from_pivot(state, {})
    assert_eq(_sorted_keys(reach), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
            "whole graph reachable with nothing removed")


func test_reachable_from_pivot_removing_branch_root_orphans_only_its_tail() -> void:
    var state := _branchy_cycle_state()
    var reach := BladePopResolver._reachable_from_pivot(state, {5: true})
    assert_eq(_sorted_keys(reach), [0, 1, 2, 3, 4, 7, 8, 9],
            "6 was only reachable through 5; the rest — including the cycle — stands")


func test_reachable_from_pivot_a_redundant_cycle_vertex_disconnects_nothing() -> void:
    var state := _branchy_cycle_state()
    # 3 sits on the cycle but the 2-7-8-9-4 detour still reaches everything
    # past it once 3 alone is gone.
    var reach := BladePopResolver._reachable_from_pivot(state, {3: true})
    assert_eq(_sorted_keys(reach), [0, 1, 2, 4, 5, 6, 7, 8, 9],
            "the cycle's alternate path keeps 4/7/8/9 reachable without 3")


func test_reachable_from_pivot_removing_the_cut_vertex_orphans_everything_downstream() -> void:
    var state := _branchy_cycle_state()
    # 2 is the sole gateway to BOTH the branch (5-6) and the cycle (3-4-7-8-9):
    # both of the cycle's entry edges, (2,3) and (2,7), are incident to it.
    var reach := BladePopResolver._reachable_from_pivot(state, {2: true})
    assert_eq(_sorted_keys(reach), [0, 1],
            "removing the true cut vertex takes the branch AND the whole cycle with it")


# ── _kill via LiveGate.admit: exact dead_at contents + severance cascade ─────

## Two sequential pops in one swing: first the branch root (5), then the true
## cut vertex (2). Pins the exact dead_at map after each step, including the
## cycle fragment {3,4,7,8,9} disintegrating together once its sole gateway
## is gone — despite forming a cycle among themselves.
func test_kill_cascade_pins_dead_at_across_two_sequential_pops() -> void:
    var ctx: Dictionary = await _setup()
    var state := _branchy_cycle_state()
    var gate := BladePopResolver.LiveGate.new(state, ctx.attacker)

    # Pop 1: vertex 5 (branch root) at t=0.3. Kills 5, disintegrates 6.
    assert_false(gate.admit(_ev(0.3, 5, ctx.spike_node), CombatWorld.live()),
            "the popping contact deals no damage")
    assert_eq(gate.result.dead_at, {5: 0.3, 6: 0.3},
            "vertex 5 killed, its only downstream vertex 6 disintegrates with it")
    assert_eq(gate.result.pops.size(), 1, "one killing contact so far")

    # Pop 2: vertex 2 (the true cut vertex) at t=0.6. Cuts off the branch's
    # already-dead remainder AND the entire cycle fragment {3,4,7,8,9} in one
    # stroke, since both of the cycle's attachment edges are incident to 2.
    assert_false(gate.admit(_ev(0.6, 2, ctx.spike_node), CombatWorld.live()))
    assert_eq(gate.result.dead_at,
            {5: 0.3, 6: 0.3, 2: 0.6, 3: 0.6, 4: 0.6, 7: 0.6, 8: 0.6, 9: 0.6},
            "cutting vertex 2 takes the whole downstream cycle fragment with it")
    assert_eq(gate.result.pops.size(), 2, "two killing contacts")

    # Only the pivot and the one spine vertex ahead of the cut survive.
    for v in [0, 1]:
        assert_false(gate.result.dead_at.has(v), "vertex %d survives both pops" % v)
