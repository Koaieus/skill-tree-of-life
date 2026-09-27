extends GutTest

## The loot round's controller is [LootRoundCommandHandler]: it sequences a
## relic's phases (stat rounds -> the spell round -> terminal), waits on each
## human pick through the [LootPickRegistry] on its [CommandContext], and lands
## every outcome through the addon's public grant/finish contract. The addon
## only describes what it offers.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")


## Records the addon's landing contract instead of mutating a board.
class _RecordingDust extends SkillDustAddon:
	var calls: Array[String] = []

	func grant_mod(_collector: Entity, m: StatModifier) -> void:
		calls.append("mod:%s" % m.stat_id)

	func grant_spell(_collector: Entity, spell: SpellDef) -> void:
		calls.append("spell:%s" % spell.id)

	func finish() -> void:
		calls.append("finish")


## Every collector is "remote", so every pick parks in the registry and the
## test answers it the way a returning PickLootCommand would.
class _AlwaysRemoteRegistry extends LootPickRegistry:
	func is_remote_collector(_collector: Entity) -> bool:
		return true


func _mod(id: StringName, v: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = v
	return m


func test_the_handler_lands_mod_then_spell_then_finish() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var relic := _SKILL_NODE_SCENE.instantiate() as SkillNode
	graph.skill_nodes_container.add_child(relic)
	var collector: Entity = Entity.new()
	collector.display_name = "Collector"
	graph.entities_container.add_child(collector)
	await get_tree().process_frame

	var dust := _RecordingDust.new()
	dust.candidates = [_mod(&"armor", 1.0), _mod(&"strength", 2.0)] as Array[StatModifier]
	dust.weights = [1.0, 1.0] as Array[float]
	dust.rounds = 1
	dust.spell_candidates = [SpellCatalog.SPARK] as Array[SpellDef]
	relic.add_child(dust)

	var registry := _AlwaysRemoteRegistry.new()
	add_child_autofree(registry)
	var parked: Array = []
	registry.offer_parked.connect(func(request: Variant) -> void: parked.append(request))

	var ctx := CommandContext.new()
	ctx.graph = graph
	ctx.loot_pick_registry = registry

	LootRoundCommandHandler.new().open_round(dust, collector, ctx)

	assert_eq(parked.size(), 1, "the stat round offers a real 2-way choice and waits on it")
	if parked.size() != 1:
		return
	assert_eq(parked[0].candidates.size(), 2)
	var picked_stat: StringName = parked[0].candidates[0].stat_id
	assert_true(registry.resolve_pick(parked[0].request_id, 0))

	assert_eq(parked.size(), 2, "the spell round follows the last stat round")
	if parked.size() != 2:
		return
	assert_true(parked[1] is SpellLootRequest)
	assert_true(registry.resolve_pick(parked[1].request_id, 0))

	assert_eq(dust.calls, ["mod:%s" % picked_stat, "spell:%s" % SpellCatalog.SPARK.id, "finish"]
			as Array[String], "mod -> spell -> finish, in order, through the addon's contract")
