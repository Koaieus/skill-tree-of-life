extends GutTest

## A rider is any [HitInstance] (#1480, ADR 0049): an arrow carries its
## landing's [member HitInstance.hit_key], so "the riders of arrow i" are the
## later hits sharing it ([method ArrowVolleyCoordinator.riders_of]); the key
## rides [AttackRecord]; and a [DamageInstance] rider gates on
## [member HitInstance.paired] and [member HitInstance.land_mask] exactly as a
## status does, a rebuilt one never re-gating.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")
const _BLINDNESS_ARROW: AmmoType = preload("res://attack/ammo/types/blindness.tres")


## Attacker owns core–leaf; the defender owns target + hostile_a + hostile_b;
## the target also touches the attacker's own `mine` node and an unallocated
## `neutral` one.
func _build() -> Dictionary:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var nodes: Dictionary = {}
	var names := ["core", "leaf", "target", "hostile_a", "hostile_b", "mine", "neutral"]
	for i in names.size():
		var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
		node.name = str(names[i])
		graph.add_skill_node(node)
		node.global_position = Vector2(150 * i, 0)
		nodes[names[i]] = node
	graph.add_edge(nodes.core, nodes.leaf)
	graph.add_edge(nodes.leaf, nodes.mine)
	graph.add_edge(nodes.mine, nodes.target)
	graph.add_edge(nodes.target, nodes.hostile_a)
	graph.add_edge(nodes.target, nodes.hostile_b)
	graph.add_edge(nodes.target, nodes.neutral)

	var attacker := Entity.new()
	attacker.display_name = "Attacker"
	attacker.faction = _PLAYER_FACTION
	attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.entities_container.add_child(attacker)
	var defender := Entity.new()
	defender.display_name = "Defender"
	defender.faction = _NPC_FACTION
	defender.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.entities_container.add_child(defender)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	for n in ["core", "leaf", "mine"]:
		alloc.force_allocate(attacker, nodes[n])
	attacker.core_location = nodes.core
	for n in ["hostile_a", "target", "hostile_b"]:
		alloc.force_allocate(defender, nodes[n])
	defender.core_location = nodes.hostile_a
	await get_tree().process_frame
	return {"graph": graph, "attacker": attacker, "defender": defender, "nodes": nodes}



## [plain arrow, blindness arrow, its three splashed riders].
func _volley(ctx: Dictionary) -> Array[HitInstance]:
	var hits: Array[HitInstance] = []
	hits.append(RangedDamageFormula.compute(ctx.attacker, ctx.nodes.leaf, ctx.nodes.target))
	var typed := RangedDamageFormula.compute(ctx.attacker, ctx.nodes.leaf, ctx.nodes.target, _BLINDNESS_ARROW)
	hits.append(typed)
	hits.append_array(RangedDamageFormula.riders_for(typed))
	return hits


func test_a_plain_arrow_has_no_riders_and_a_typed_one_has_exactly_its_own() -> void:
	var ctx: Dictionary = await _build()
	var hits := _volley(ctx)
	assert_eq(hits.size(), 5, "plain + typed + three splashed riders")
	assert_eq(hits[0].hit_key, 0, "a bare arrow mints no landing")
	assert_true(ArrowVolleyCoordinator.riders_of(hits, 0, false).is_empty(), "keyless: no riders")
	assert_true(ArrowVolleyCoordinator.riders_of(hits, 0, true).is_empty())
	assert_ne(hits[1].hit_key, 0, "the typed arrow takes its landing's key")
	var all := ArrowVolleyCoordinator.riders_of(hits, 1, false)
	assert_eq(all, hits.slice(2) as Array[HitInstance], "every rider, splashed ones included")
	var same := ArrowVolleyCoordinator.riders_of(hits, 1, true)
	assert_eq(same.size(), 1, "only the rider on the arrow's own target")
	assert_eq(same[0].target if not same.is_empty() else null, ctx.nodes.target)


func test_the_shared_key_survives_the_record_round_trip() -> void:
	var ctx: Dictionary = await _build()
	var outcome := AttackOutcome.new()
	outcome.hits = _volley(ctx)
	OutcomeApplier.apply(outcome, CombatWorld.live())
	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, ctx.graph)))
	var rebuilt := AttackRecord.rebuild(wired, ctx.graph)
	assert_eq(rebuilt.hits.size(), 5)
	assert_eq(rebuilt.hits[0].hit_key, 0, "a bare arrow stays keyless")
	assert_eq(rebuilt.hits[1].hit_key, outcome.hits[1].hit_key, "the arrow's key rides the record")
	for j in range(2, rebuilt.hits.size()):
		assert_eq(rebuilt.hits[j].hit_key, rebuilt.hits[1].hit_key, "a rebuilt rider shares its arrow's key")
	assert_eq(ArrowVolleyCoordinator.riders_of(rebuilt.hits, 1, false).size(), 3,
			"a peer's coordinator finds the same riders")


func _damage(ctx: Dictionary, on: SkillNode) -> DamageInstance:
	var hit := DamageInstance.new()
	hit.type = DamageInstance.Type.TRUE
	hit.amount = 5.0
	hit.attacker = ctx.attacker
	hit.target = on
	return hit


func test_a_damage_rider_of_a_gated_hit_lands_as_a_dud() -> void:
	var ctx: Dictionary = await _build()
	var primary := DamageInstance.new()
	primary.gated = true
	var hit := _damage(ctx, ctx.nodes.target)
	hit.paired = primary
	var combat: NodeCombat = ctx.nodes.target.get_combat()
	var before := combat.get_current_hp()
	hit.land_on(combat, CombatWorld.live())
	assert_true(hit.gated, "rides its primary's dud")
	assert_eq(hit.amount, 0.0, "power 0")
	assert_eq(combat.get_current_hp(), before, "nothing landed")


func test_a_damage_rider_masked_hostile_duds_on_the_attackers_own_node() -> void:
	var ctx: Dictionary = await _build()
	var hit := _damage(ctx, ctx.nodes.mine)
	hit.land_mask = SkillNode.Ownership.HOSTILE
	var combat: NodeCombat = ctx.nodes.mine.get_combat()
	var before := combat.get_current_hp()
	hit.land_on(combat, CombatWorld.live())
	assert_true(hit.gated, "the node is not hostile at land")
	assert_eq(combat.get_current_hp(), before, "nothing landed")


func test_a_rebuilt_damage_hit_never_re_gates() -> void:
	var ctx: Dictionary = await _build()
	var outcome := AttackOutcome.new()
	outcome.hits.append(_damage(ctx, ctx.nodes.target))
	OutcomeApplier.apply(outcome, CombatWorld.live())
	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, ctx.graph)))
	var twin: HitInstance = AttackRecord.rebuild(wired, ctx.graph).hits[0]
	assert_true(twin.land_resolved, "the authority already decided")
	twin.land_mask = SkillNode.Ownership.HOSTILE
	var combat: NodeCombat = ctx.nodes.mine.get_combat()
	var before := combat.get_current_hp()
	twin.land_on(combat, CombatWorld.live())
	assert_false(twin.gated, "a rebuilt hit lands what the authority recorded")
	assert_lt(combat.get_current_hp(), before, "and it lands")
