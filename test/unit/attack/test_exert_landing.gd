extends GutTest

## The exertion landing: one [ExertInstance] per node of an attack's origin set
## (ranged — the leaves that fired; melee — every node copied onto the blade;
## magic — the source plus its owned neighbours), landing on the first beat and
## running [method StatusDef._on_exerted] on that node's rows. A core exerts by
## moving, once per turn, on its ENTITY host.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")


## Counts [method _on_exerted] per REAL host — a shadow slice reports the node
## it clones, so a resolve on a shadow world counts against the board's nodes.
class SpyDef extends StatusDef:
	var calls: Dictionary = {}

	func _on_exerted(host) -> void:
		var key: Variant = host
		if host is NodeCombat:
			key = (host as NodeCombat).real()
		elif host is EntityCombat:
			key = (host as EntityCombat).real_entity()
		calls[key] = int(calls.get(key, 0)) + 1

	func count(key: Variant) -> int:
		return int(calls.get(key, 0))


var _spy: SpyDef


func before_each() -> void:
	_spy = SpyDef.new()
	_spy.id = &"exert_spy"


func _set_local(node: SkillNode, stat_id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


func _exerts(outcome: AttackOutcome) -> Array[HitInstance]:
	var out: Array[HitInstance] = []
	for hit in outcome.hits:
		if hit is ExertInstance:
			out.append(hit)
	return out


func _targets(hits: Array[HitInstance]) -> Array:
	var out := []
	for hit in hits:
		out.append(hit.target)
	return out


## Attacker owns core–leaf (and, with [param third], core–leaf2); defender owns
## target–neighbour. The target sits ON the leaf so a swing contacts it at t=0.
func _build(third: bool = false) -> Dictionary:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var nodes: Dictionary = {}
	var layout := [["core", Vector2(0, 0)], ["leaf", Vector2(150, 0)],
			["target", Vector2(150, 0)], ["neighbour", Vector2(300, 0)]]
	if third:
		layout.append(["leaf2", Vector2(0, 150)])
	for entry in layout:
		var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
		node.name = str(entry[0])
		graph.add_skill_node(node)
		node.global_position = entry[1] as Vector2
		nodes[entry[0]] = node
	graph.add_edge(nodes.core, nodes.leaf)
	graph.add_edge(nodes.leaf, nodes.target)
	graph.add_edge(nodes.target, nodes.neighbour)
	if third:
		graph.add_edge(nodes.core, nodes.leaf2)

	var attacker := Entity.new()
	attacker.faction = _PLAYER_FACTION
	attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	attacker.stat_board.arrows.add(AmmoTypeRoster.BASE_ID, 40)
	attacker.stat_board.blade_size.base_value = 3.0
	attacker.stat_board.action_points.base_value = 4.0
	attacker.stat_board.action_points.current = 4.0
	attacker.stat_board.movement_points.base_value = 10.0
	attacker.stat_board.movement_points.current = 10.0
	graph.entities_container.add_child(attacker)
	var defender := Entity.new()
	defender.faction = _NPC_FACTION
	defender.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.entities_container.add_child(defender)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(attacker, nodes.core)
	alloc.force_allocate(attacker, nodes.leaf)
	if third:
		alloc.force_allocate(attacker, nodes.leaf2)
	attacker.core_location = nodes.core
	alloc.force_allocate(defender, nodes.target)
	alloc.force_allocate(defender, nodes.neighbour)
	defender.core_location = nodes.neighbour
	_set_local(nodes.leaf, &"range", 400.0)
	_set_local(nodes.leaf, &"ranged_damage", 5.0)

	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.start_turn(attacker)
	var bs := BattleSystem.new()
	bs.turn_manager = tm
	bs.allocation_system = alloc
	bs.graph = graph
	bs.instant_mutation = true
	add_child_autofree(bs)

	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	return {"graph": graph, "bs": bs, "alloc": alloc, "attacker": attacker, "nodes": nodes}


func _spy_on(nodes: Array) -> void:
	for n in nodes:
		(n as SkillNode).get_combat().apply_status(_spy, 3.0)


func _ranged(ctx: Dictionary) -> RangedAttackPlan:
	var plan := (ctx.bs as BattleSystem).new_plan(
			BattleSystem.AttackMode.RANGED, ctx.attacker) as RangedAttackPlan
	plan.set_target(ctx.nodes.target)
	return plan


## The distinct firing nodes of a ranged outcome's arrows.
func _firers(outcome: AttackOutcome) -> Array:
	var out := []
	for hit in outcome.hits:
		if hit is DamageInstance and hit.origin != null and not out.has(hit.origin):
			out.append(hit.origin)
	return out


# ── 1. Ranged ───────────────────────────────────────────────────────────────

func test_a_volley_exerts_each_firing_leaf_once_on_the_first_beat() -> void:
	var ctx: Dictionary = await _build()
	_spy_on([ctx.nodes.core, ctx.nodes.leaf])
	var outcome := _ranged(ctx).resolve()
	var firers := _firers(outcome)
	assert_eq(firers.size(), 2, "precondition: core and leaf both fire")
	var exerts := _exerts(outcome)
	assert_eq(exerts.size(), 2, "one EXERT per firing leaf")
	for f in firers:
		assert_true(_targets(exerts).has(f), "%s fired, so it exerts" % f)
		assert_eq(_spy.count(f), 1, "%s exerts once however many arrows it fired" % f)
	var first := INF
	for hit in outcome.hits:
		first = minf(first, hit.arrival_time)
	for e in exerts:
		assert_eq(e.arrival_time, first, "an exertion lands on the first beat")
		assert_eq(e.kind, HitInstance.Kind.EXERT, "EXERT kind")


# ── 2. Melee ────────────────────────────────────────────────────────────────

func test_a_swing_exerts_the_pivot_and_every_copied_node() -> void:
	var ctx: Dictionary = await _build(true)
	var blade := [ctx.nodes.core, ctx.nodes.leaf, ctx.nodes.leaf2]
	_spy_on(blade)
	var plan := (ctx.bs as BattleSystem).new_plan(
			BattleSystem.AttackMode.MELEE, ctx.attacker) as MeleeAttackPlan
	plan.set_pivot(ctx.nodes.core)
	plan.toggle_member(ctx.nodes.leaf)
	plan.toggle_member(ctx.nodes.leaf2)
	var outcome := plan.resolve()
	var exerts := _exerts(outcome)
	assert_eq(exerts.size(), 3, "pivot + two copied nodes")
	for n in blade:
		assert_true(_targets(exerts).has(n), "%s is on the blade, so it exerts" % n)
		assert_eq(_spy.count(n), 1, "%s exerts once" % n)


# ── 3. Magic ────────────────────────────────────────────────────────────────

func test_a_cast_exerts_the_source_and_its_owned_neighbours_only() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [0, 2], [0, 3]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, atk, [0, 1, 2])
	helper.assign_owner(graph, def, [3])
	await get_tree().process_frame
	var n := graph.get_skill_nodes()
	_spy_on([n[0], n[1], n[2], n[3]])
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.max_reducer(),
			{max_hops = 1})
	var on_hits: Array[OnHitEffect] = [DamageEffect.new()]
	var spell := helper.make_spell(config, on_hits, 10.0)
	var outcome := SpellResolver.resolve(spell, n[3], n[0], atk, graph)
	var exerts := _exerts(outcome)
	assert_eq(exerts.size(), 3, "source + two owned neighbours")
	for i in [0, 1, 2]:
		assert_true(_targets(exerts).has(n[i]), "node %d exerts" % i)
		assert_eq(_spy.count(n[i]), 1, "node %d exerts once" % i)
	assert_false(_targets(exerts).has(n[3]), "an enemy neighbour never exerts")
	assert_eq(_spy.count(n[3]), 0, "the enemy's rows are never told")


# ── 4. Off the wire ─────────────────────────────────────────────────────────

func test_a_rebuilt_record_exerts_the_same_on_a_live_replay() -> void:
	var ctx: Dictionary = await _build()
	_spy_on([ctx.nodes.core, ctx.nodes.leaf])
	var outcome := _ranged(ctx).resolve()
	var record := AttackRecord.capture(outcome, ctx.graph)
	# The same outcome without its exertions keys the record identically.
	var bare := AttackOutcome.new()
	bare.cadence = outcome.cadence
	bare.resolve_seed = outcome.resolve_seed
	for hit in outcome.hits:
		if not hit is ExertInstance:
			bare.hits.append(hit)
	var bare_keys := AttackRecord.capture(bare, ctx.graph).keys()
	bare_keys.sort()
	var keys := record.keys()
	keys.sort()
	assert_eq(keys, bare_keys, "the record carries no new key")
	_spy.calls.clear()
	var wired: Dictionary = bytes_to_var(var_to_bytes(record))
	var rebuilt := AttackRecord.rebuild(wired, ctx.graph)
	assert_eq(_exerts(rebuilt).size(), 2, "the rebuild mints the exertions back")
	await OutcomeApplier.apply(rebuilt, CombatWorld.live())
	assert_eq(_spy.count(ctx.nodes.core), 1, "the replay exerts the core leaf once")
	assert_eq(_spy.count(ctx.nodes.leaf), 1, "the replay exerts the leaf once")


# ── 5. Shot accounting ──────────────────────────────────────────────────────

func test_exertions_burn_no_shot() -> void:
	var ctx: Dictionary = await _build()
	var plan := _ranged(ctx)
	var outcome := plan.resolve()
	var arrows := 0
	for hit in outcome.hits:
		if hit is DamageInstance:
			arrows += 1
	assert_gt(_exerts(outcome).size(), 0, "precondition: the volley exerted")
	(ctx.bs as BattleSystem)._consume_volley(plan, outcome)
	var fired := 0
	for n in [ctx.nodes.core, ctx.nodes.leaf]:
		fired += (n as SkillNode).shots_fired_this_turn
	assert_eq(fired, arrows, "one shot per arrow, none per exertion")


# ── 6. The core move ────────────────────────────────────────────────────────

func test_a_core_exerts_its_entity_host_once_per_turn_by_moving() -> void:
	var ctx: Dictionary = await _build()
	var attacker: Entity = ctx.attacker
	attacker.get_combat().apply_status(_spy, 3.0)
	_spy_on([ctx.nodes.core, ctx.nodes.leaf])
	var cc := CommandContext.new()
	cc.graph = ctx.graph
	cc.allocation_system = ctx.alloc
	cc.tree = get_tree()
	var handler := MoveCoreCommandHandler.new()
	var there := MoveCoreCommand.new(0, [ctx.nodes.leaf.stable_id] as Array[int])
	var back := MoveCoreCommand.new(0, [ctx.nodes.core.stable_id] as Array[int])
	assert_true(await handler._apply(there, attacker, cc), "first move lands")
	assert_true(await handler._apply(back, attacker, cc), "second move lands")
	assert_eq(attacker.core_location, ctx.nodes.core, "precondition: the core walked back")
	assert_eq(_spy.count(attacker), 1, "the mover's entity host exerts once per turn")
	assert_eq(_spy.count(ctx.nodes.core), 0, "the node the core left/reached never exerts")
	assert_eq(_spy.count(ctx.nodes.leaf), 0, "the node the core reached never exerts")
