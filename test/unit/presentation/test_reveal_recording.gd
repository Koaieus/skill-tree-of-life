extends GutTest

## #490 — the six RevealRecorder call sites + three cause scopes wired into
## the mutation loop. Pins timeline SHAPE only (events, order, `t` values) —
## nothing consumes the timeline yet (that's #491). The old hold machinery
## stays live and untouched throughout; these tests never assert on it.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")


func _set_stat(node: SkillNode, id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


func _add_node(graph: Graph, at: Vector2) -> SkillNode:
	var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
	n.position = at
	graph.add_skill_node(n)
	return n


func _events_for(tl: RevealTimeline, kind: RevealEvent.Kind) -> Array[RevealEvent]:
	var out: Array[RevealEvent] = []
	for e in tl.events:
		if e.kind == kind:
			out.append(e)
	return out


# ── Fixture 1: cascade — cut vertex t1 islands t2 (mirrors
# test_cascade_presentation_clock.gd) ───────────────────────────────────────

func _build_cascade() -> Dictionary:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)

	var core := _add_node(graph, Vector2(0, 0))
	var leaf := _add_node(graph, Vector2(200, 0))
	graph.add_edge(core, leaf)

	var t1 := _add_node(graph, Vector2(250, 0))
	var t2 := _add_node(graph, Vector2(300, -100))
	var hcore := _add_node(graph, Vector2(350, 0))
	graph.add_edge(hcore, t1)
	graph.add_edge(t1, t2)

	var attacker := Entity.new()
	attacker.faction = _PLAYER_FACTION
	attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	attacker.stat_board.action_points.set_base_ratcheted(2.0)
	attacker.stat_board.action_points.current = 2.0
	graph.add_child(attacker)

	var hostile := Entity.new()
	hostile.faction = _NPC_FACTION
	hostile.color = Color(0.1, 0.9, 0.3)
	hostile.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.add_child(hostile)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(attacker, core)
	alloc.force_allocate(attacker, leaf)
	attacker.core_location = core
	alloc.force_allocate(hostile, hcore)
	alloc.force_allocate(hostile, t1)
	alloc.force_allocate(hostile, t2)
	hostile.core_location = hcore

	_set_stat(leaf, &"range", 100.0)
	_set_stat(leaf, &"ranged_damage", 9999.0)
	_set_stat(core, &"range", 0.0)

	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.current_entity = attacker

	var bs := BattleSystem.new()
	bs.turn_manager = tm
	bs.allocation_system = alloc
	bs.graph = graph
	add_child_autofree(bs)

	return {"bs": bs, "alloc": alloc, "hostile": hostile,
			"leaf": leaf, "t1": t1, "t2": t2, "hcore": hcore}


func _fire_at(bs: BattleSystem, target: SkillNode) -> void:
	bs.request_attack_mode(BattleSystem.AttackMode.RANGED)
	var plan := bs.attack_plan as RangedAttackPlan
	plan._on_node_left_clicked(target)
	assert_true(plan.is_valid(), "fixture plan must be valid before launching")
	bs.launch_attack()


func test_cascade_order_pins_death_ordering() -> void:
	var ctx: Dictionary = await _build_cascade()
	var bs: BattleSystem = ctx.bs
	var t1: SkillNode = ctx.t1

	_fire_at(bs, t1)

	var tl: RevealTimeline = bs.last_reveal_timeline
	assert_not_null(tl, "launch_attack must record a timeline")

	var impact_events: Array[RevealEvent] = []
	for e in tl.events:
		if e.node == t1:
			impact_events.append(e)
	assert_eq(impact_events.size(), 3,
			"impact node must record NODE_HP, NODE_DEATH, NODE_OWNER_LOST")
	assert_eq(impact_events[0].kind, RevealEvent.Kind.NODE_HP)
	assert_eq(impact_events[1].kind, RevealEvent.Kind.NODE_DEATH)
	assert_eq(impact_events[2].kind, RevealEvent.Kind.NODE_OWNER_LOST)
	assert_eq(impact_events[0].t, impact_events[1].t,
			"NODE_HP and NODE_DEATH share the impact's t")
	assert_eq(impact_events[1].t, impact_events[2].t,
			"NODE_DEATH and NODE_OWNER_LOST share the impact's t")


func test_cascade_stagger_offsets_the_islanded_layer() -> void:
	var ctx: Dictionary = await _build_cascade()
	var bs: BattleSystem = ctx.bs
	var t1: SkillNode = ctx.t1
	var t2: SkillNode = ctx.t2

	_fire_at(bs, t1)

	var tl: RevealTimeline = bs.last_reveal_timeline
	var t1_owner_lost: RevealEvent = null
	var t2_owner_lost: RevealEvent = null
	for e in tl.events:
		if e.kind == RevealEvent.Kind.NODE_OWNER_LOST:
			if e.node == t1:
				t1_owner_lost = e
			elif e.node == t2:
				t2_owner_lost = e
	assert_not_null(t1_owner_lost, "layer 0's owner-lost event must be recorded")
	assert_not_null(t2_owner_lost, "layer 1's owner-lost event must be recorded")
	assert_almost_eq(t2_owner_lost.t, t1_owner_lost.t + RevealTimeline.CASCADE_STEP, 0.001,
			"layer 1 lands exactly one CASCADE_STEP after layer 0")


# ── Multi-hit volley: three attacker leaves reach the same hostile core ────

func _build_volley() -> Dictionary:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)

	var core := _add_node(graph, Vector2(0, 0))
	# Clustered near `core` and far from `target` so all three fly (almost)
	# equal distances — flight-time jitter must stay well under
	# RangedDamageFormula.LAUNCH_STAGGER (0.2s) or arrival order (and so
	# record/chain order) stops matching firing order.
	var leaf_a := _add_node(graph, Vector2(0, 50))
	var leaf_b := _add_node(graph, Vector2(0, -50))
	var leaf_c := _add_node(graph, Vector2(50, 0))
	graph.add_edge(core, leaf_a)
	graph.add_edge(core, leaf_b)
	graph.add_edge(core, leaf_c)

	var target := _add_node(graph, Vector2(1000, 0))

	var attacker := Entity.new()
	attacker.faction = _PLAYER_FACTION
	attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	attacker.stat_board.action_points.set_base_ratcheted(2.0)
	attacker.stat_board.action_points.current = 2.0
	graph.add_child(attacker)

	var hostile := Entity.new()
	hostile.faction = _NPC_FACTION
	hostile.color = Color(0.1, 0.9, 0.3)
	hostile.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.add_child(hostile)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(attacker, core)
	alloc.force_allocate(attacker, leaf_a)
	alloc.force_allocate(attacker, leaf_b)
	alloc.force_allocate(attacker, leaf_c)
	attacker.core_location = core
	alloc.force_allocate(hostile, target)
	hostile.core_location = target

	# Small, non-lethal per-hit damage against the ~10 HP default node_health
	# pool — the volley must land three times without killing the target,
	# which would fold NODE_DEATH into this fixture and complicate the chain
	# assertion.
	for leaf in [leaf_a, leaf_b, leaf_c]:
		_set_stat(leaf, &"range", 1100.0)
		_set_stat(leaf, &"ranged_damage", 2.0)

	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.current_entity = attacker

	var bs := BattleSystem.new()
	bs.turn_manager = tm
	bs.allocation_system = alloc
	bs.graph = graph
	add_child_autofree(bs)

	return {"bs": bs, "target": target}


func test_multi_hit_volley_chains_from_to_at_distinct_t() -> void:
	var ctx: Dictionary = await _build_volley()
	var bs: BattleSystem = ctx.bs
	var target: SkillNode = ctx.target

	bs.request_attack_mode(BattleSystem.AttackMode.RANGED)
	var plan := bs.attack_plan as RangedAttackPlan
	plan._on_node_left_clicked(target)
	assert_eq(plan.get_reaching_firing_positions().size(), 3,
			"fixture: all three leaves must reach the target")
	bs.launch_attack()

	var tl: RevealTimeline = bs.last_reveal_timeline
	var hp_events := _events_for(tl, RevealEvent.Kind.NODE_HP)
	assert_eq(hp_events.size(), 3, "three hits must record three NODE_HP events")

	var ts: Array[float] = []
	for e in hp_events:
		ts.append(e.t)
	var distinct_ts: Dictionary[float, bool] = {}
	for t in ts:
		distinct_ts[t] = true
	assert_eq(distinct_ts.size(), 3, "each hit's arrival_time must produce a distinct t")

	for i in range(1, hp_events.size()):
		assert_eq(hp_events[i].from_value, hp_events[i - 1].to_value,
				"hit %d's from must chain off the previous hit's to" % i)


# ── Direct core kill: one hit overflows health and empties it in one blow ──

func _build_direct_core_kill() -> Dictionary:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)

	var core := _add_node(graph, Vector2(0, 0))
	var leaf := _add_node(graph, Vector2(200, 0))
	graph.add_edge(core, leaf)

	var hcore := _add_node(graph, Vector2(250, 0))
	var n1 := _add_node(graph, Vector2(400, 0))
	var n2 := _add_node(graph, Vector2(550, 0))
	graph.add_edge(hcore, n1)
	graph.add_edge(n1, n2)

	var attacker := Entity.new()
	attacker.faction = _PLAYER_FACTION
	attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	attacker.stat_board.action_points.set_base_ratcheted(2.0)
	attacker.stat_board.action_points.current = 2.0
	graph.add_child(attacker)

	var hostile := Entity.new()
	hostile.faction = _NPC_FACTION
	hostile.color = Color(0.1, 0.9, 0.3)
	hostile.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.add_child(hostile)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(attacker, core)
	alloc.force_allocate(attacker, leaf)
	attacker.core_location = core
	alloc.force_allocate(hostile, hcore)
	alloc.force_allocate(hostile, n1)
	alloc.force_allocate(hostile, n2)
	hostile.core_location = hcore

	_set_stat(leaf, &"range", 100.0)
	# Overkill: empties hcore's own combat HP AND the entity's `health` pool
	# in the same hit, one-shotting the entity — the case the old (predictive)
	# machinery could not do without a core special-case.
	_set_stat(leaf, &"ranged_damage", 99999.0)
	_set_stat(core, &"range", 0.0)

	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.current_entity = attacker

	var bs := BattleSystem.new()
	bs.turn_manager = tm
	bs.allocation_system = alloc
	bs.graph = graph
	add_child_autofree(bs)

	return {"bs": bs, "hostile": hostile, "hcore": hcore, "n1": n1, "n2": n2}


func test_direct_core_kill_records_entity_health_then_death_then_strip() -> void:
	var ctx: Dictionary = await _build_direct_core_kill()
	var bs: BattleSystem = ctx.bs
	var hcore: SkillNode = ctx.hcore
	var hostile: Entity = ctx.hostile

	_fire_at(bs, hcore)

	var tl: RevealTimeline = bs.last_reveal_timeline
	assert_not_null(tl, "launch_attack must record a timeline")

	var health_events := _events_for(tl, RevealEvent.Kind.ENTITY_HEALTH)
	var death_events := _events_for(tl, RevealEvent.Kind.ENTITY_DEATH)
	var owner_lost_events := _events_for(tl, RevealEvent.Kind.NODE_OWNER_LOST)

	assert_eq(health_events.size(), 1, "the core-overflow branch records one ENTITY_HEALTH event")
	assert_eq(health_events[0].entity, hostile)
	assert_eq(death_events.size(), 1, "die() records exactly one ENTITY_DEATH event")
	assert_eq(death_events[0].entity, hostile)
	# hcore, n1, n2 — every node the entity owned — must each lose ownership,
	# staggered by CASCADE_STEP, with no special-casing for the core node.
	assert_eq(owner_lost_events.size(), 3,
			"the whole territory (core included) is stripped on death")

	var health_i := tl.events.find(health_events[0])
	var death_i := tl.events.find(death_events[0])
	assert_true(health_i < death_i, "ENTITY_HEALTH must record before ENTITY_DEATH")
	for e in owner_lost_events:
		var i := tl.events.find(e)
		assert_true(death_i < i, "NODE_OWNER_LOST strip events must record after ENTITY_DEATH")

	var stagger_ts: Array[float] = []
	for e in owner_lost_events:
		stagger_ts.append(e.t)
	stagger_ts.sort()
	for i in range(1, stagger_ts.size()):
		assert_almost_eq(stagger_ts[i], stagger_ts[i - 1] + RevealTimeline.CASCADE_STEP, 0.001,
				"the death strip staggers each node by CASCADE_STEP")


# ── Pass-through: force_deallocate with no timeline open ───────────────────

func test_pass_through_records_nothing_and_applies_immediately() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var node := _add_node(graph, Vector2(0, 0))

	var owner := Entity.new()
	owner.faction = _NPC_FACTION
	owner.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.add_child(owner)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(owner, node)

	assert_false(RevealRecorder.is_recording, "no attack is in flight")
	alloc.force_deallocate(node)

	assert_null(node.owned_by, "a sandbox-style call applies immediately, timeline or not")
