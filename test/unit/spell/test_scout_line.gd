extends GutTest

## The scout line, "Flare Line" (`attack/spell/defs/scout_line.tres`): an aimed
## line from the cast-from node lands one `scouted` stack for the caster's camp
## on every node it crosses, whoever owns it, fog included. Driven through the
## real launch path (BattleSystem build → prepare → apply).

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")
const _SCOUTED: ScoutStatus = preload("res://effects/status/scouted.tres")

var _graph: Graph
var _bs: BattleSystem
var _vision: VisionSystem
var _attacker: Entity
var _defender: Entity
var _nodes: Dictionary = {}


## Attacker owns back–core; the line fires east (angle 0) from core at the
## origin through hostile (150), neutral (250) and far (380, hostile, fogged).
## `outside` sits beside neutral, 1 px past the band's reach.
func before_each() -> void:
	_nodes = {}
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	for entry in [["back", Vector2(-100, 0)], ["core", Vector2.ZERO],
			["hostile", Vector2(150, 0)], ["neutral", Vector2(250, 0)],
			["far", Vector2(380, 0)], ["outside", Vector2(250, 0)]]:
		var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
		node.name = str(entry[0])
		_graph.add_skill_node(node)
		node.global_position = entry[1]
		_nodes[entry[0]] = node
	var band := (SpellCatalog.SCOUT_LINE.targeting as AimedTargeting).shape as LineShape
	var outside := _nodes.outside as SkillNode
	outside.global_position = Vector2(250, band.width + outside.radius + 1.0)
	_graph.add_edge(_nodes.back, _nodes.core)
	_graph.add_edge(_nodes.core, _nodes.hostile)
	_graph.add_edge(_nodes.hostile, _nodes.neutral)
	_graph.add_edge(_nodes.neutral, _nodes.far)
	_graph.add_edge(_nodes.neutral, _nodes.outside)

	_attacker = _entity("Attacker", _PLAYER_FACTION)
	_defender = _entity("Defender", _NPC_FACTION)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = _graph
	add_child_autofree(alloc)
	alloc.force_allocate(_attacker, _nodes.back)
	alloc.force_allocate(_attacker, _nodes.core)
	_attacker.core_location = _nodes.core
	alloc.force_allocate(_defender, _nodes.hostile)
	alloc.force_allocate(_defender, _nodes.far)
	_defender.core_location = _nodes.far

	_set_local(_nodes.back, &"vision_range", 50.0)
	_set_local(_nodes.core, &"vision_range", 260.0)

	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.start_turn(_attacker)

	_bs = BattleSystem.new()
	_bs.turn_manager = tm
	_bs.allocation_system = alloc
	_bs.graph = _graph
	_bs.instant_mutation = true
	add_child_autofree(_bs)

	_vision = VisionSystem.new()
	_vision.graph = _graph
	_vision.viewers = [_attacker]
	_vision.ease_rate = 0.0
	add_child_autofree(_vision)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_vision._recompute()
	assert_false(_vision.is_visible(_nodes.far), "fixture: far sits in the fog")


func _entity(nm: String, faction: Faction) -> Entity:
	var en := Entity.new()
	en.display_name = nm
	en.faction = faction
	en.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(en)
	return en


func _set_local(node: SkillNode, stat_id: StringName, value: float,
		op: StatModifier.Operation = StatModifier.Operation.SET) -> void:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = op
	m.value = value
	node.add_local_modifier(m)


func _launch(angle: float) -> void:
	var plan := _bs.new_plan(BattleSystem.AttackMode.MAGIC, _attacker) as MagicAttackPlan
	plan.set_spell(SpellCatalog.SCOUT_LINE)
	assert_true(plan.set_aim(_nodes.core, angle), "core is an eligible caster")
	assert_eq(plan.validate(), [] as Array[String], "source + aim is a complete plan")
	var command := _bs.build_launch_command(plan)
	assert_not_null(command, "the aimed plan must be launchable")
	if command == null:
		return
	assert_true(_bs.prepare_launch_command(command), "the cast must survive validation")
	@warning_ignore("redundant_await")
	await _bs.apply_launch_command(command)


func _row(node_name: String) -> float:
	return (_nodes[node_name] as SkillNode).get_combat().get_status_power(
			_SCOUTED.id, _PLAYER_FACTION.id)


func test_every_crossed_node_gains_one_stack_for_the_caster_camp() -> void:
	await _launch(0.0)
	for nm in ["hostile", "neutral", "far"]:
		assert_eq(_row(nm), 1.0, "%s is crossed: one scouted stack for the caster's camp" % nm)
		assert_eq((_nodes[nm] as SkillNode).get_combat().get_status_power(
				_SCOUTED.id, _NPC_FACTION.id), 0.0, "%s: nothing for the other camp" % nm)
	assert_eq(_row("outside"), 0.0, "1 px past the band gets nothing")
	assert_eq(_row("core"), 0.0, "the source is never a seed")


func test_vision_recompute_marks_the_crossed_nodes_scouted_fog_included() -> void:
	await _launch(0.0)
	_vision._recompute()
	for nm in ["hostile", "neutral", "far"]:
		assert_true((_nodes[nm] as SkillNode).scouted, "%s reads scouted for the caster" % nm)
	assert_false((_nodes.outside as SkillNode).scouted, "outside the band stays unscouted")


## Ratio, not literal: doubling `cast_range_distance` on the source lengthens
## the crossed set along a long straight row.
func test_doubled_cast_range_crosses_more_of_a_long_row() -> void:
	var targeting := SpellCatalog.SCOUT_LINE.targeting as AimedTargeting
	var row: Array[SkillNode] = []
	for i in range(1, 13):
		var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
		_graph.add_skill_node(n)
		n.global_position = Vector2(0, -100.0 * i)
		row.append(n)
	var up := -PI / 2.0
	var before := targeting.seeds(_attacker, _nodes.core, up, _graph)
	_set_local(_nodes.core, &"cast_range_distance", 2.0, StatModifier.Operation.MULTIPLY)
	var after := targeting.seeds(_attacker, _nodes.core, up, _graph)
	assert_gt(before.size(), 0, "the authored reach crosses some of the row")
	assert_lt(before.size(), row.size(), "the authored reach stops short of the row's end")
	assert_almost_eq(float(after.size()) / float(before.size()), 2.0, 0.35,
			"double the reach, about double the crossed nodes")
