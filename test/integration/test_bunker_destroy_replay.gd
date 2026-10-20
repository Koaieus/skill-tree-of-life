extends GutTest

## #1634 acceptance 2 + 5 — a destroy decided on the shadow reaches the live
## world only through the record, and a save taken after it keeps it gone.


const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BUNKER_SCENE := preload("res://skill_node/addons/defs/bunker_addon.tscn")
const _SPACING := 150.0
## A point the floppy whip's free tip passes through (test_bunker_break_live).
const _PLATE := Vector2(-253.0, -204.5)


func _spawn(graph: Graph, nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	graph.add_skill_node(sn)
	sn.global_position = pos
	return sn


func _make_entity(graph: Graph) -> Entity:
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = _BOARD.duplicate(true)
	entity.stat_board.get_stat(&"crit_chance").base_value = 0.0
	entity.turns_taken = 1
	graph.add_child(entity)
	return entity


## The floppy whip of test_bunker_break_live, every member bunkered (uniform
## mass leaves the free swing unchanged), into a bunkered defender whose
## threshold is [param threshold].
func _setup(threshold: float) -> Dictionary:
	var graph := TestWorld.create(self).graph
	var attacker := _make_entity(graph)
	var defender := _make_entity(graph)
	var enemy_camp := Faction.new()
	enemy_camp.id = &"bunker_destroy_enemy"
	defender.faction = enemy_camp
	var pivot := _spawn(graph, "Pivot", Vector2.ZERO)
	var a := _spawn(graph, "A", Vector2(_SPACING, 0.0))
	var b := _spawn(graph, "B", Vector2(_SPACING * 2.0, 0.0))
	var tip := _spawn(graph, "Tip", Vector2(_SPACING * 3.0, 0.0))
	graph.add_edge(pivot, a)
	graph.add_edge(a, b)
	graph.add_edge(b, tip)
	var bunker := _spawn(graph, "Bunker", _PLATE)
	await get_tree().process_frame
	var alloc := TestWorld.allocator_for(graph)
	for n in [pivot, a, b, tip]:
		alloc.force_allocate(attacker, n)
	attacker.core_location = pivot
	alloc.force_allocate(defender, bunker)
	defender.core_location = bunker
	for n in [a, b, tip]:
		n.add_child(_BUNKER_SCENE.instantiate())
	var plate := _BUNKER_SCENE.instantiate() as BunkerAddon
	plate.destroy_momentum = threshold
	bunker.add_child(plate)
	var sharp := StatModifier.new()
	sharp.stat_id = &"blade_damage"
	sharp.operation = StatModifier.Operation.ADD_BONUS
	sharp.value = 5.0
	tip.add_local_modifier(sharp)
	b.add_local_modifier(sharp)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var plan := MeleeAttackPlan.new()
	plan.attacker = attacker
	plan.source = pivot
	plan.blade_nodes = [a, b, tip]
	return {"bunker": bunker, "plan": plan, "graph": graph, "alloc": alloc}


static func _destroys(outcome: AttackOutcome) -> Array[HitInstance]:
	var out: Array[HitInstance] = []
	for hit in outcome.hits:
		if hit.kind == HitInstance.Kind.ADDON_DESTROY:
			out.append(hit)
	return out


static func _has_bunker(sn: SkillNode) -> bool:
	for addon in sn.get_addons():
		if addon is BunkerAddon:
			return true
	return false


func test_below_the_threshold_the_defender_keeps_its_bunker() -> void:
	var ctx: Dictionary = await _setup(1e12)
	var shadow := CombatWorld.shadow()
	var outcome := (ctx.plan as MeleeAttackPlan).resolve_against(shadow)
	shadow.free_shadow()
	assert_eq(_destroys(outcome).size(), 0, "a clang destroys nothing")
	assert_true(_has_bunker(ctx.bunker), "the defender keeps its Bunker")


func test_above_the_threshold_the_resolve_records_one_destroy_and_frees_nothing() -> void:
	var ctx: Dictionary = await _setup(1e-3)
	var shadow := CombatWorld.shadow()
	var outcome := (ctx.plan as MeleeAttackPlan).resolve_against(shadow)
	shadow.free_shadow()
	var destroys := _destroys(outcome)
	assert_eq(destroys.size(), 1, "one destroy for the one bunkered defender")
	if destroys.size() == 1:
		assert_eq(destroys[0].target, ctx.bunker, "it names the defender's node")
	assert_true(_has_bunker(ctx.bunker), "only the replay frees the live addon")
	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, ctx.graph)))
	assert_eq(_destroys(AttackRecord.rebuild(wired, ctx.graph)).size(), 1,
			"the destroy survives the wire")


func test_a_replayed_destroy_frees_the_live_bunker_and_survives_a_save() -> void:
	var ctx: Dictionary = await _setup(1e-3)
	var graph: Graph = ctx.graph
	var bunker: SkillNode = ctx.bunker
	var shadow := CombatWorld.shadow()
	var outcome := (ctx.plan as MeleeAttackPlan).resolve_against(shadow)
	shadow.free_shadow()
	assert_true(_has_bunker(bunker), "precondition: the resolve freed nothing live")
	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, graph)))
	OutcomeApplier.apply(AttackRecord.rebuild(wired, graph), CombatWorld.live(), null, ctx.alloc)
	assert_false(_has_bunker(bunker), "the replayed record knocked the Bunker off")

	var saved := GraphSnapshot.encode(graph)
	bunker.add_child(_BUNKER_SCENE.instantiate())
	await get_tree().process_frame
	GraphSnapshot.decode(saved, graph)
	await get_tree().process_frame
	assert_false(_has_bunker(bunker), "a save taken after the destroy loads without it")
