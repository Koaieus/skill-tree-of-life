extends GutTest

## #530 — BladeHitScan.scan() stable-sorts its own output: `t` is the
## gameplay-meaningful primary key, and a tie (two colliders newly hit in the
## SAME query, whose relative order Godot's broadphase does not define)
## breaks on SkillNode.stable_id — a value every peer agrees on. Since
## MeleeAttackPlan pops defensive spikes DURING its trajectory scan, an
## unpinned tie could change WHICH spikes pop, not just the arithmetic
## (see blade_hit_scan.gd's class docstring and attack-timeline.md).
##
## test_stable_sort_orders_a_tie_by_stable_id_not_arrival_order pins the sort
## itself, independent of physics — the mechanism this issue is closing.
## test_same_plan_resolves_an_identical_hit_sequence_twice is the acceptance
## claim end to end, through a real swing.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _SPIKE_SCENE := preload("res://skill_node/addons/spike_ring_addon.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")


func _spawn(graph: Graph, nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	graph.add_skill_node(sn)
	sn.global_position = pos
	return sn


# ── The sort itself, isolated from physics ──────────────────────────────────

## Hands the sort a same-`t` triple in the OPPOSITE of stable_id order — the
## shape an adversarial broadphase could return — and asserts the sort, not
## the query, is what fixes the order.
func test_stable_sort_orders_a_tie_by_stable_id_not_arrival_order() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var a := _spawn(graph, "A", Vector2.ZERO)
	var b := _spawn(graph, "B", Vector2.ZERO)
	var c := _spawn(graph, "C", Vector2.ZERO)
	# Force minting in a KNOWN order via the graph, per graph.md — reading
	# node.stable_id directly before this would read zeroes for all three.
	graph.get_stable_id(a)
	graph.get_stable_id(b)
	graph.get_stable_id(c)
	assert_true(a.stable_id < b.stable_id and b.stable_id < c.stable_id,
			"fixture assumption: ids mint in spawn order")

	var events: Array[BladeHitEvent] = [
		BladeHitEvent.new(0.5, 2, -1, c),
		BladeHitEvent.new(0.5, 0, -1, a),
		BladeHitEvent.new(0.5, 1, -1, b),
	]
	BladeHitScan._stable_sort(events, graph)
	var order: Array[SkillNode] = [events[0].target, events[1].target, events[2].target]
	assert_eq(order, [a, b, c],
			"a same-t tie breaks on stable_id, never on the order the query handed them in")


func test_stable_sort_keeps_t_as_the_primary_key() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var a := _spawn(graph, "A", Vector2.ZERO)
	var b := _spawn(graph, "B", Vector2.ZERO)
	graph.get_stable_id(a)
	graph.get_stable_id(b)
	# b has the LATER stable_id but the EARLIER contact time — time must win.
	var events: Array[BladeHitEvent] = [
		BladeHitEvent.new(0.9, 0, -1, a),
		BladeHitEvent.new(0.1, 1, -1, b),
	]
	BladeHitScan._stable_sort(events, graph)
	assert_eq([events[0].target, events[1].target], [b, a],
			"arrival time stays primary; stable_id only breaks a genuine tie")


# ── End to end: the acceptance claim ────────────────────────────────────────

## Pivot(0,0)-Arm(150,0), with two hostile targets placed COINCIDENT at the
## arm's tip — the same trick test_attack_determinism.gd's melee fixture uses
## to land a hit without depending on physics-server sync timing, doubled up
## so both colliders land in the SAME query at the SAME substep: the exact
## shape whose relative order used to be broadphase-dependent. One target is
## spiked, so the pop cascade is exercised, not just the hit list.
func test_same_plan_resolves_an_identical_hit_sequence_twice() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)

	var attacker := Entity.new()
	attacker.display_name = "A"
	attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	attacker.faction = _PLAYER_FACTION
	attacker.stat_board.blade_size.base_value = 2.0
	graph.add_child(attacker)

	var defender := Entity.new()
	defender.display_name = "D"
	defender.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	defender.stat_board.get_stat(&"node_health").base_value = 9999.0
	graph.add_child(defender)

	var pivot := _spawn(graph, "Pivot", Vector2.ZERO)
	var arm := _spawn(graph, "Arm", Vector2(150, 0))
	graph.add_edge(pivot, arm)

	var target_a := _spawn(graph, "TargetA", Vector2(150, 0))
	var target_b := _spawn(graph, "TargetB", Vector2(150, 0))
	var spike := _SPIKE_SCENE.instantiate() as SpikeRingAddon
	var mod := StatModifier.new()
	mod.stat_id = &"blade_damage"
	mod.operation = StatModifier.Operation.ADD_BONUS
	mod.value = 5.0
	spike.local_modifiers = [mod]
	target_a.add_child(spike)

	await get_tree().process_frame
	alloc.force_allocate(attacker, pivot)
	alloc.force_allocate(attacker, arm)
	attacker.core_location = pivot
	alloc.force_allocate(defender, target_a)
	alloc.force_allocate(defender, target_b)
	defender.core_location = target_a
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var hit_sequences: Array = []
	var pop_sequences: Array = []
	for _i in 2:
		var plan := MeleeAttackPlan.new()
		plan.attacker = attacker
		plan._on_node_left_clicked(pivot)
		plan._on_node_left_clicked(arm)
		plan.resolve_seed = 0xA11CE
		var outcome := plan.resolve()
		var hit_ids: Array[int] = []
		for hit in outcome.hits:
			hit_ids.append(graph.get_stable_id(hit.target as SkillNode))
		hit_sequences.append(hit_ids)
		var pop_ids: Array[int] = []
		for pop in plan.last_pops.pops:
			pop_ids.append(graph.get_stable_id(pop.defender))
		pop_sequences.append(pop_ids)

	assert_false(hit_sequences[0].is_empty(), "fixture produced no blade contacts")
	assert_eq(hit_sequences[0], hit_sequences[1],
			"the same plan + seed against the same graph must land the same hits in the same order")
	assert_eq(pop_sequences[0], pop_sequences[1],
			"and pop the same spikes in the same order")
