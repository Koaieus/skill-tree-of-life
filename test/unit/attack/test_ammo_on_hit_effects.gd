extends GutTest

## An arrow's on-hit riders are [member AmmoType.on_hit_effects] — the shared
## [OnHitEffect] vocabulary (ADR 0044). [method RangedDamageFormula.riders_for]
## runs every effect against one [HitLanding] paired to the arrow, so an
## authored type may carry several riders: each lands on the arrow's beat, in
## authored order, and a dud arrow takes them all down with it. Spell-only
## effects are refused from the slot at load.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")
const _POISON_DEF: StatusDef = preload("res://effects/status/poison.tres")
const _TEST_DEF: StatusDef = preload("res://test/fixtures/status/test_status.tres")

## Small, so a default-HP target survives the arrow and keeps its statuses.
const _BASE_DAMAGE := 1.0


class _SpellOnly extends SpellOnHitEffect:
	func _apply_spell(_lctx: LandingContext) -> void:
		pass


func _rider(def: StatusDef, power: float = 1.0) -> ApplyStatusEffect:
	var e := ApplyStatusEffect.new()
	e.def = def
	e.power = power
	return e


func _two_rider_type() -> AmmoType:
	var t := AmmoType.new()
	t.id = &"two_rider"
	t.damage_scale = 1.0
	t.on_hit_effects = [_rider(_POISON_DEF), _rider(_TEST_DEF, 2.0)] as Array[OnHitEffect]
	return t


func _set_local(node: SkillNode, stat_id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


## Attacker owns core–leaf, defender owns target–neighbour.
func _build() -> Dictionary:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var nodes: Dictionary = {}
	for entry in [["core", Vector2(0, 0)], ["leaf", Vector2(150, 0)],
			["target", Vector2(300, 0)], ["neighbour", Vector2(450, 0)]]:
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
	attacker.core_location = nodes.core
	alloc.force_allocate(defender, nodes.target)
	alloc.force_allocate(defender, nodes.neighbour)
	defender.core_location = nodes.neighbour
	_set_local(nodes.leaf, &"ranged_damage", _BASE_DAMAGE)
	await get_tree().process_frame
	return {"graph": graph, "attacker": attacker, "nodes": nodes}


## The arrow, then its riders — the order [RangedAttackPlan] appends them in.
func _fire(ctx: Dictionary, type: AmmoType) -> AttackOutcome:
	var outcome := AttackOutcome.new()
	var hit := RangedDamageFormula.compute(ctx.attacker, ctx.nodes.leaf, ctx.nodes.target, type)
	hit.structural_key = 0.375
	outcome.hits.append(hit)
	outcome.hits.append_array(RangedDamageFormula.riders_for(hit))
	return outcome


func _power(node: SkillNode, id: StringName) -> float:
	return node.get_combat().get_status_power(id)


func test_two_status_riders_land_after_the_arrow_on_its_key_in_authored_order() -> void:
	var ctx: Dictionary = await _build()
	var outcome := _fire(ctx, _two_rider_type())
	var hits := outcome.hits
	assert_eq(hits.size(), 3, "the arrow, then one hit per rider")
	if hits.size() != 3:
		return
	assert_eq(hits[0].kind, HitInstance.Kind.DAMAGE, "the arrow lands first")
	var a := hits[1] as StatusInstance
	var b := hits[2] as StatusInstance
	assert_eq([a.def, b.def], [_POISON_DEF, _TEST_DEF], "riders in authored order")
	assert_eq([a.power, b.power], [1.0, 2.0], "each rider at its own authored power")
	for s: StatusInstance in [a, b]:
		assert_eq(s.structural_key, 0.375, "a rider shares its arrow's beat")
		assert_eq(s.paired, hits[0], "a rider is gated by its arrow")
		assert_eq(s.target, ctx.nodes.target)
		assert_eq(s.origin, ctx.nodes.leaf)
		assert_eq(s.attacker, ctx.attacker)
		assert_eq(s.ammo_type_id, &"two_rider", "the rider still says which arrow carried it")
	OutcomeApplier.apply(outcome, CombatWorld.live())
	assert_false(hits[0].gated)
	assert_gt(_power(ctx.nodes.target, &"poison"), 0.0, "poison landed")
	assert_gt(_power(ctx.nodes.target, &"test_status"), 0.0, "the second status landed too")


func test_a_gated_arrow_lands_neither_status() -> void:
	var ctx: Dictionary = await _build()
	var outcome := _fire(ctx, _two_rider_type())
	assert_eq(outcome.hits.size(), 3, "fixture: arrow + two riders")
	# The target fell to an earlier arrow's kill cascade before this one lands.
	(ctx.nodes.target as SkillNode).owned_by = null
	OutcomeApplier.apply(outcome, CombatWorld.live())
	assert_false(RangedDamageFormula.passes_gate(ctx.attacker, ctx.nodes.target.get_combat(),
			ctx.nodes.leaf.get_combat()), "sanity: the arrow fails the gate")
	for h: HitInstance in outcome.hits:
		assert_true(h.gated, "every hit of a dud landing is a dud")
	assert_eq(_power(ctx.nodes.target, &"poison"), 0.0)
	assert_eq(_power(ctx.nodes.target, &"test_status"), 0.0)


func test_a_type_without_riders_emits_none() -> void:
	var ctx: Dictionary = await _build()
	var bare := AmmoType.new()
	var hit := RangedDamageFormula.compute(ctx.attacker, ctx.nodes.leaf, ctx.nodes.target, bare)
	assert_eq(RangedDamageFormula.riders_for(hit).size(), 0)
	var untyped := RangedDamageFormula.compute(ctx.attacker, ctx.nodes.leaf, ctx.nodes.target)
	assert_eq(RangedDamageFormula.riders_for(untyped).size(), 0, "no ammo type, nothing to run")


func test_the_card_lists_every_riders_description() -> void:
	var t := _two_rider_type()
	var line := AmmoCard.effect_line(t)
	for e: OnHitEffect in t.on_hit_effects:
		assert_string_contains(line, e.get_description())


func test_a_spell_only_effect_is_refused_from_the_slot() -> void:
	var t := AmmoType.new()
	var kept := _rider(_POISON_DEF)
	t.on_hit_effects = [_SpellOnly.new(), kept] as Array[OnHitEffect]
	assert_push_error("spell-only")
	assert_eq(t.on_hit_effects, [kept] as Array[OnHitEffect], "the spell effect is dropped, the rest kept")
