extends GutTest

## The aimed-spell gesture end to end through [PlayerInputController]: press
## on an eligible caster, drag, release. The aim follows the drag vector, a
## press off the union arms nothing, the preview re-resolves only when the
## crossed set changes, and predicted hit marks respect the viewer's fog.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")


## Fog double: only the nodes in [member seen] are visible.
class FogStub extends VisionSystem:
	var seen: Dictionary = {}

	func is_visible(node: SkillNode) -> bool:
		return seen.has(node)


## The catalog holds no aimed spell yet, so SPARK is borrowed and restored.
var _spark: SpellDef = SpellCatalog.SPARK
var _spark_targeting: Targeting

var _graph: Graph
var _ctl: PlayerInputController
var _attacker: Entity
var _source: SkillNode
var _back: SkillNode
var _east1: SkillNode
var _east2: SkillNode
var _north: SkillNode


func _node(pos: Vector2) -> SkillNode:
	var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
	n.position = pos
	_graph.add_skill_node(n)
	return n


func before_each() -> void:
	_spark_targeting = _spark.targeting
	var t := AimedTargeting.new()
	t.shape = LineShape.new()
	t.ownership_filter = 1 | 8
	t.range_finder = EuclideanRangeFinder.new()
	t.range_finder.max_distance = 450.0
	_spark.targeting = t

	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_back = _node(Vector2(-100, 0))
	_source = _node(Vector2.ZERO)
	_east1 = _node(Vector2(100, 0))
	_east2 = _node(Vector2(200, 0))
	_north = _node(Vector2(0, -150))
	_graph.add_edge(_back, _source)
	_graph.add_edge(_source, _east1)
	_graph.add_edge(_east1, _east2)
	_graph.add_edge(_source, _north)

	_attacker = autofree(Entity.new())
	_attacker.faction = _PLAYER_FACTION
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_attacker)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = _graph
	add_child_autofree(alloc)
	alloc.force_allocate(_attacker, _back)
	alloc.force_allocate(_attacker, _source)

	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.start_turn(_attacker)

	var battle := BattleSystem.new()
	battle.turn_manager = tm
	battle.allocation_system = alloc
	battle.graph = _graph
	add_child_autofree(battle)

	_ctl = PlayerInputController.new()
	_ctl.graph = _graph
	_ctl.allocation_system = alloc
	_ctl.battle_system = battle
	_ctl.turn_manager = tm
	add_child_autofree(_ctl)
	_ctl.player = _attacker


func after_each() -> void:
	_spark.targeting = _spark_targeting


func _arm() -> MagicAttackPlan:
	_ctl.armed_stack.selected_spell = _spark
	_ctl.arm_attack(BattleSystem.AttackMode.MAGIC)
	var plan := _ctl.armed_stack.attack_plan() as MagicAttackPlan
	assert_not_null(plan, "fixture: magic arms a MagicAttackPlan")
	assert_eq(plan.spell, _spark, "fixture: the aimed spell is equipped")
	assert_true(plan.is_aimed(), "fixture: the equipped spell is aimed")
	assert_true(plan.union().is_source(_source), "fixture: the source is an eligible caster")
	return plan


func _move(world: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _graph.get_global_transform_with_canvas() * world
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	_ctl._unhandled_input(ev)


func _release() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	_ctl._unhandled_input(ev)


func test_press_drag_release_commits_the_aim() -> void:
	var plan := _arm()
	_ctl.route_left_click(_source)
	_move(Vector2(150, 150))
	_release()
	assert_eq(plan.source, _source, "the pressed caster is the plan's source")
	assert_almost_eq(plan.aim_angle, PI / 4.0, 0.001, "the aim follows the drag vector")
	assert_eq(plan.validate(), [] as Array[String], "the committed aim validates")
	assert_true(_ctl.armed_stack.top() is TargetMode, "release commits like a clicked target")
	var visual := plan.get_range_visual()
	assert_eq(visual.shapes.size(), 1, "the reach visual carries the aimed shape")
	assert_eq(visual.shapes[0].length, (_spark.targeting as AimedTargeting).length(_attacker, _source),
			"drawn to the full reach length")


func test_press_on_a_non_source_sets_no_aim() -> void:
	var plan := _arm()
	_ctl.route_left_click(_east1)
	_move(Vector2(150, 150))
	_release()
	assert_null(plan.source, "no source stamped")
	assert_true(is_nan(plan.aim_angle), "no aim set")
	assert_false(_ctl.armed_stack.top() is TargetMode, "nothing committed")


func test_preview_resolves_only_when_the_crossed_set_changes() -> void:
	var plan := _arm()
	_ctl.route_left_click(_source)
	_move(Vector2(300, 0))
	plan.preview_outcome()
	var after_first := plan.preview_resolves
	assert_gt(after_first, 0, "the first aim resolves a preview")
	assert_eq(plan.get_node_role(_east1), HighlightProvider.HighlightRole.PROPAGATION,
			"fixture: the aim east crosses east1")
	_move(Vector2(300, 2))
	plan.preview_outcome()
	_move(Vector2(300, -3))
	plan.preview_outcome()
	assert_eq(plan.preview_resolves, after_first, "same crossed set, no re-resolve")
	_move(Vector2(0, -300))
	plan.preview_outcome()
	assert_eq(plan.preview_resolves, after_first + 1, "a new crossed set re-resolves once")


func test_predicted_hits_mark_only_seen_nodes() -> void:
	var plan := _arm()
	var fog: FogStub = autofree(FogStub.new())
	fog.seen = {_back: true, _source: true, _east1: true}
	plan.viewer_vision = fog
	_ctl.route_left_click(_source)
	_move(Vector2(300, 0))
	assert_eq(plan.get_node_role(_east1), HighlightProvider.HighlightRole.PROPAGATION,
			"a seen crossed node is marked")
	assert_ne(plan.get_node_role(_east2), HighlightProvider.HighlightRole.PROPAGATION,
			"a fogged crossed node gets no mark")
