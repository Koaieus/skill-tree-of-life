extends GutTest

## The flare (#1390): a [SplashEffect] runs its inner effect on the landed node
## and once more per direct graph neighbour HOSTILE to the attacker, each copy
## sharing the arrow's hit key and paired gate. A splashed rider whose node is
## no longer hostile at land is a dud.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")
const _BLINDNESS_ARROW: AmmoType = preload("res://attack/ammo/types/blindness.tres")
const _BLINDNESS_DEF_PATH := "res://effects/status/blindness.tres"


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


func _riders(ctx: Dictionary) -> Dictionary:
	var hit := RangedDamageFormula.compute(ctx.attacker, ctx.nodes.leaf, ctx.nodes.target, _BLINDNESS_ARROW)
	return {"hit": hit, "riders": RangedDamageFormula.riders_for(hit)}


func _inner_power() -> float:
	var effect: Variant = _BLINDNESS_ARROW.on_hit_effects[0]
	if not (effect is SplashEffect) or not (effect.inner is ApplyStatusEffect):
		return -1.0
	return effect.inner.power


func test_a_blindness_arrow_blinds_the_target_and_its_hostile_neighbours_only() -> void:
	var ctx: Dictionary = await _build()
	var r := _riders(ctx)
	var hit: HitInstance = r.hit
	var riders: Array[HitInstance] = r.riders
	var targets: Array = []
	for rider in riders:
		var status := rider as StatusInstance
		assert_not_null(status, "every splashed rider is a status")
		assert_eq(status.def.resource_path, _BLINDNESS_DEF_PATH)
		assert_eq(status.power, _inner_power(), "the authored power on every node")
		assert_eq(status.paired, hit, "every rider rides the arrow's gate")
		assert_eq(status.hit_key, riders[0].hit_key, "one hit: one key")
		targets.append(status.target)
	assert_eq(riders.size(), 3, "target + two hostile neighbours")
	assert_ne(riders[0].hit_key if not riders.is_empty() else 0, 0)
	assert_true(targets.has(ctx.nodes.target))
	assert_true(targets.has(ctx.nodes.hostile_a))
	assert_true(targets.has(ctx.nodes.hostile_b))
	assert_false(targets.has(ctx.nodes.mine), "never the attacker's own node")
	assert_false(targets.has(ctx.nodes.neutral), "never a neutral node")


func test_the_wrapped_status_still_names_the_type() -> void:
	assert_eq(_BLINDNESS_ARROW.first_status_def().resource_path, _BLINDNESS_DEF_PATH,
			"tint, card badge and roster checks read the status through the wrapper")
	assert_false(_BLINDNESS_ARROW.is_scout(), "zero damage is never a scout")


func test_a_neighbour_no_longer_hostile_at_land_takes_a_dud() -> void:
	var ctx: Dictionary = await _build()
	var r := _riders(ctx)
	assert_eq(r.riders.size(), 3)
	ctx.nodes.hostile_b.owned_by = null
	var world := CombatWorld.live()
	(r.hit as HitInstance).land_on(ctx.nodes.target.get_combat(), world)
	for rider: HitInstance in r.riders:
		var status := rider as StatusInstance
		status.land_on(status.target.get_combat(), world)
		if status.target == ctx.nodes.hostile_b:
			assert_true(status.gated, "the neighbour left the defender's hands: a dud")
			assert_eq(status.power, 0.0)
		else:
			assert_false(status.gated, "%s still hostile" % status.target.name)
			assert_gt(status.power, 0.0)


func test_a_gated_arrow_duds_every_splashed_rider() -> void:
	var ctx: Dictionary = await _build()
	var r := _riders(ctx)
	assert_eq(r.riders.size(), 3)
	ctx.nodes.target.owned_by = null
	var world := CombatWorld.live()
	(r.hit as HitInstance).land_on(ctx.nodes.target.get_combat(), world)
	assert_true((r.hit as HitInstance).gated)
	for rider: HitInstance in r.riders:
		var status := rider as StatusInstance
		status.land_on(status.target.get_combat(), world)
		assert_true(status.gated, "%s shares the arrow's dud" % status.target.name)
		assert_eq(status.power, 0.0)


func test_an_ammo_type_accepts_a_splash_and_a_spell_may_carry_one() -> void:
	var splash: OnHitEffect = SplashEffect.new()
	assert_false(splash is SpellOnHitEffect, "mode-agnostic: not a spell-only effect")
	var ammo := AmmoType.new()
	ammo.on_hit_effects = [splash] as Array[OnHitEffect]
	assert_eq(ammo.on_hit_effects.size(), 1, "AmmoType keeps a SplashEffect")
	var spell := SpellDef.new()
	spell.on_hit_effects = [splash] as Array[OnHitEffect]
	assert_eq(spell.on_hit_effects.size(), 1, "a spell carries one too")
