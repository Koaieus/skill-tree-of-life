extends GutTest

## The aimed-spell gesture end to end through [PlayerInputController]: the
## shape snaps to the eligible caster nearest the hovering cursor and points
## at it, a left click locks it, a right-click unlocks back to hover. A cursor
## inside the caster's disc names no direction, the preview re-resolves only
## when the crossed set changes, and predicted hit marks respect the viewer's
## fog.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")


## Fog double: only the nodes in [member seen] are visible.
class FogStub extends VisionSystem:
	var seen: Dictionary = {}

	func is_visible(node: SkillNode) -> bool:
		return seen.has(node)


## SPARK is borrowed and its targeting swapped (and restored) to drive the aim input over a known def.
var _spark: SpellDef = SpellCatalog.SPARK
var _spark_targeting: Targeting

var _graph: Graph
var _ctl: PlayerInputController
var _alloc: AllocationSystem
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
	_alloc = alloc
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
	_ctl.armed_stack.select_spell(_ctl.player, _spark)
	_ctl.arm_attack(BattleSystem.AttackMode.MAGIC)
	var plan := _ctl.armed_stack.attack_plan() as MagicAttackPlan
	assert_not_null(plan, "fixture: magic arms a MagicAttackPlan")
	assert_eq(plan.spell, _spark, "fixture: the aimed spell is equipped")
	assert_true(plan.is_aimed(), "fixture: the equipped spell is aimed")
	assert_true(plan.union().is_source(_source), "fixture: the source is an eligible caster")
	return plan


## A hover: no button held.
func _move(world: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _graph.get_global_transform_with_canvas() * world
	_ctl._unhandled_input(ev)


## A left click over empty space — node-independent, like the lock itself.
func _click() -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		_ctl._unhandled_input(ev)


func _right_click() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	_ctl._unhandled_input(ev)


func test_hover_snaps_to_the_nearest_caster() -> void:
	var plan := _arm()
	assert_true(plan.union().is_source(_back), "fixture: back is a second eligible caster")
	_move(Vector2(-150, 50))
	assert_eq(plan.source, _back, "the caster nearest the cursor is the source")
	assert_almost_eq(plan.aim_angle, 3.0 * PI / 4.0, 0.001, "aimed from that caster at the cursor")
	_move(Vector2(150, 150))
	assert_eq(plan.source, _source, "the snap follows the cursor to the other caster")
	assert_almost_eq(plan.aim_angle, PI / 4.0, 0.001, "aimed from the new caster")
	assert_false(_ctl.armed_stack.top() is TargetMode, "hovering locks nothing")


func test_click_locks_the_aim() -> void:
	var plan := _arm()
	_move(Vector2(150, 150))
	_click()
	assert_eq(plan.source, _source, "the snapped caster is the plan's source")
	assert_almost_eq(plan.aim_angle, PI / 4.0, 0.001, "the aim follows the cursor")
	assert_eq(plan.validate(), [] as Array[String], "the locked aim validates")
	assert_true(_ctl.armed_stack.top() is TargetMode, "a click locks like a clicked target")
	_move(Vector2(-150, 50))
	assert_eq(plan.source, _source, "a locked aim ignores the hover")
	assert_almost_eq(plan.aim_angle, PI / 4.0, 0.001, "a locked angle ignores the hover")
	var visual := plan.get_range_visual()
	assert_eq(visual.shapes.size(), 1, "the reach visual carries the aimed shape")
	assert_eq(visual.shapes[0].length, (_spark.targeting as AimedTargeting).length(_attacker, _source),
			"drawn to the full reach length")


func test_right_click_unlocks_back_to_hover() -> void:
	var plan := _arm()
	_move(Vector2(150, 150))
	_click()
	assert_true(_ctl.armed_stack.top() is TargetMode, "fixture: locked")
	_right_click()
	assert_true(_ctl.armed_stack.top() is MagicMode, "right-click pops back to hover-aim")
	_move(Vector2(-150, 50))
	assert_eq(plan.source, _back, "the shape follows the mouse again")
	assert_almost_eq(plan.aim_angle, 3.0 * PI / 4.0, 0.001, "re-aimed at the cursor")


func test_one_caster_aims_from_it_everywhere() -> void:
	_alloc.force_deallocate(_back)
	var plan := _arm()
	assert_eq(plan.union().sources.size(), 1, "fixture: one eligible caster")
	for world: Vector2 in [Vector2(-300, 0), Vector2(0, 300), Vector2(500, -500)]:
		_move(world)
		assert_eq(plan.source, _source, "every cursor aims from the lone caster")
		assert_almost_eq(plan.aim_angle, world.angle(), 0.001, "pointed at the cursor")


func test_a_click_inside_the_caster_commits_nothing() -> void:
	var plan := _arm()
	_move(Vector2(2, 1))
	_click()
	assert_true(is_nan(plan.aim_angle), "a cursor inside the caster's disc sets no aim")
	assert_false(_ctl.armed_stack.top() is TargetMode, "nothing committed")


func test_preview_resolves_only_when_the_crossed_set_changes() -> void:
	var plan := _arm()
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
	_move(Vector2(300, 0))
	assert_eq(plan.get_node_role(_east1), HighlightProvider.HighlightRole.PROPAGATION,
			"a seen crossed node is marked")
	assert_ne(plan.get_node_role(_east2), HighlightProvider.HighlightRole.PROPAGATION,
			"a fogged crossed node gets no mark")
