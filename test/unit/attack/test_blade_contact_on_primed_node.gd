extends GutTest

## A blade contact is one hit, nothing more: the piece holds no charge and
## spends none, so a piece copied off a Catalyst node lands like any other. A
## Burning struck node goes off through the gather as any hit sets it off; a
## node holding only Catalyst blasts nothing and keeps its stacks.
##
## Gate-level cases place the contact's landing as [SwingResolve] does; the
## swing case runs a real [MeleeAttackPlan] so the head is the swing's own.
##
## Board: VolleyBoardFixture — target (450,0) hostile; cluster[0] (600,0)
## hostile; the attacker owns the hub and the leaves.

const _CATALYST_PATH := "res://effects/status/catalyst.tres"
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

var _f: VolleyBoardFixture


func after_each() -> void:
	CombatWorld.reset_live()


func _board() -> void:
	CombatWorld.reset_live()
	_f = await VolleyBoardFixture.build(self, true)
	_f.target.base_radius = 40.0


func _catalyst() -> StatusDef:
	return load(_CATALYST_PATH) as StatusDef


func _fire_element() -> Element:
	return ElementRoster.shared().by_id(&"fire")


func _charge(node: SkillNode, n: float) -> void:
	node.get_combat().apply_status(_catalyst(), n)


func _charges(node: SkillNode) -> float:
	return node.get_combat().get_status_power(_catalyst().id)


## [param node]'s Heat set to its T + [param excess]: Burning, primed.
func _prime(node: SkillNode, excess: int) -> void:
	var c := node.get_combat()
	assert_gt(c.terrain_threshold(), 0, "fixture: %s has a T" % node.name)
	c.add_terrain(_fire_element(), c.terrain_threshold() + excess - c.terrain_t())


func _heat(node: SkillNode) -> int:
	return node.get_combat().terrain_t()


## A two-vertex blade, pivot on the hub and piece 1 on leaf_0 (which holds
## Catalyst), filled the way a swing fills it.
func _blade() -> BladeState:
	_charge(_f.leaves[0], 1.0)
	var positions: Array[Vector2] = [Vector2(-400, 0), Vector2(430, 0)]
	var radii: Array[float] = [16.0, 16.0]
	var edges: Array[Vector2i] = [Vector2i(0, 1)]
	var s := BladeState.build(positions, 0, edges, radii)
	var nodes: Array[SkillNode] = [_f.hub, _f.leaves[0]]
	BladeVertexFill.new().fill(s, nodes)
	return s


## Piece 1's contact on the target, its landing placed as [SwingResolve]
## places a contact's: the head of its own span.
func _contact(gate: BladePopResolver.LiveGate) -> Array[HitInstance]:
	var ev := BladeHitEvent.new(0.5, 1, -1, _f.target)
	var di := BladeDamageInstance.new(ev, gate)
	di.amount = 10.0
	di.type = DamageInstance.Type.PHYSICAL
	di.target = _f.target
	di.attacker = _f.attacker
	var hits: Array[HitInstance] = [di]
	var landing := HitLanding.riding(di, hits)
	landing.target_mask = SkillNode.Ownership.HOSTILE
	landing.place()
	return hits


## Land [param hits] through the gather on the live world; the copies its
## go-offs appended past the authored hits.
func _land(hits: Array[HitInstance]) -> Array[HitInstance]:
	var authored := hits.size()
	await OutcomeApplier.drain(HitQueue.over(hits), CombatWorld.live(), BeatClock.instant_clock())
	return hits.slice(authored)


func test_a_contact_on_a_burning_node_lands_one_hit_and_sets_the_disc_off() -> void:
	await _board()
	var gate := BladePopResolver.LiveGate.new(_blade(), _f.attacker)
	_prime(_f.target, 1)
	var heat := _heat(_f.target)
	var hits := _contact(gate)
	assert_eq(hits.size(), 1, "the contact is one hit: no rider, no charge")
	var copies := await _land(hits)
	assert_true((hits[0] as BladeDamageInstance).admitted, "the contact lands its hit")
	assert_lt(hits[0].hp_after, hits[0].hp_before, "and its hit damages the struck node")
	assert_true(gate.result.pops.is_empty(), "no piece pops on a contact")
	assert_eq(copies.filter(func(h): return h.target == _f.target and h is DamageInstance).size(), 1,
			"the disc's centre landing on the struck node")
	assert_lt(_heat(_f.target), heat, "the disc spent the node's Heat")


func test_a_contact_on_a_catalyst_only_node_blasts_nothing_and_spends_none() -> void:
	await _board()
	var gate := BladePopResolver.LiveGate.new(_blade(), _f.attacker)
	_charge(_f.target, 2.0)
	var held := _charges(_f.target)
	var hits := _contact(gate)
	assert_eq(hits.size(), 1, "the contact is one hit: no rider, no charge")
	var copies := await _land(hits)
	assert_true((hits[0] as BladeDamageInstance).admitted, "the contact lands its hit")
	assert_lt(hits[0].hp_after, hits[0].hp_before, "and its hit damages the struck node")
	assert_true(gate.result.pops.is_empty(), "no piece pops on a contact")
	assert_true(copies.is_empty(), "Catalyst never goes off")
	assert_eq(_charges(_f.target), held, "the struck node's Catalyst is untouched")


# --- a real swing: a plain contact is its landing's head -----------------------

func _set_local(node: SkillNode, stat_id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


## Attacker owns core–leaf; defender owns target–neighbour. The target sits ON
## the leaf so a swing contacts it at t=0.
func _swing_board() -> Dictionary:
	CombatWorld.reset_live()
	var graph: Graph = TestWorld.create(self).graph
	var nodes: Dictionary = {}
	for entry in [["core", Vector2(0, 0)], ["leaf", Vector2(150, 0)],
			["target", Vector2(150, 0)], ["neighbour", Vector2(300, 0)]]:
		var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
		node.name = str(entry[0])
		graph.add_skill_node(node)
		node.global_position = entry[1] as Vector2
		nodes[entry[0]] = node
	graph.add_edge(nodes.core, nodes.leaf)
	graph.add_edge(nodes.leaf, nodes.target)
	graph.add_edge(nodes.target, nodes.neighbour)
	var attacker := Entity.new()
	attacker.faction = _PLAYER_FACTION
	attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	attacker.stat_board.blade_size.base_value = 3.0
	attacker.stat_board.action_points.base_value = 4.0
	attacker.stat_board.action_points.current = 4.0
	graph.entities_container.add_child(attacker)
	var defender := Entity.new()
	defender.faction = _NPC_FACTION
	defender.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.entities_container.add_child(defender)
	await get_tree().process_frame
	var alloc := TestWorld.allocator_for(graph)
	alloc.force_allocate(attacker, nodes.core)
	alloc.force_allocate(attacker, nodes.leaf)
	attacker.core_location = nodes.core
	alloc.force_allocate(defender, nodes.target)
	alloc.force_allocate(defender, nodes.neighbour)
	defender.core_location = nodes.neighbour
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
	return {"bs": bs, "attacker": attacker, "nodes": nodes}


func test_a_swing_on_a_burning_node_sets_the_disc_off() -> void:
	var ctx: Dictionary = await _swing_board()
	_prime(ctx.nodes.target, 1)
	var plan := (ctx.bs as BattleSystem).new_plan(
			BattleSystem.AttackMode.MELEE, ctx.attacker) as MeleeAttackPlan
	plan.set_pivot(ctx.nodes.core)
	plan.toggle_member(ctx.nodes.leaf)
	var outcome := plan.resolve()
	var blade := outcome.hits.filter(func(h): return h is BladeDamageInstance and h.target == ctx.nodes.target)
	assert_false(blade.is_empty(), "fixture: the swing contacts the target")
	assert_true(blade.any(func(h): return h.is_head), "a plain contact heads its own landing")
	assert_true(outcome.hits.any(func(h): return h is DamageInstance and not h is BladeDamageInstance),
			"the disc's go-off copies join the swing's hits")
