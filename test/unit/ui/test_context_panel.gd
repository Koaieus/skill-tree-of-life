extends GutTest

## ContextPanel: priority resolver swaps the right pre-authored body per context
## (attack plan > core-move > pinned > idle), and every body scene loads with its
## script + @onready fields intact (guards the hand-authored-.tscn UID-strip trap
## from .claude/rules/godot-workflow.md).

const _PANEL_SCENE := preload("res://ui/context_panel/context_panel.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

const _BODY_SCENES := {
	"attack": "res://ui/context_panel/bodies/attack_plan_body.tscn",
	"core_move": "res://ui/context_panel/bodies/core_move_body.tscn",
	"pinned": "res://ui/context_panel/bodies/pinned_node_body.tscn",
	"idle": "res://ui/context_panel/bodies/idle_body.tscn",
}

var _graph: Graph
var _player: Entity
var _node: SkillNode
var _bs: BattleSystem
var _ictl: PlayerInputController
var _panel: ContextPanel


func before_each() -> void:
	_graph = Graph.new()
	_graph.skill_nodes_container = Node2D.new()
	_graph.add_child(_graph.skill_nodes_container)
	_graph.edges_container = Node2D.new()
	_graph.add_child(_graph.edges_container)
	add_child_autofree(_graph)

	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(_node)

	_player = autofree(Entity.new())
	_player.display_name = "Player"
	_player.stat_board = _BOARD.duplicate(true) as StatBoard
	_graph.add_child(_player)
	await get_tree().process_frame
	_node.owned_by = _player
	_player.core_location = _node

	_bs = autofree(BattleSystem.new())
	_ictl = autofree(PlayerInputController.new())

	_panel = _PANEL_SCENE.instantiate() as ContextPanel
	add_child_autofree(_panel)
	await get_tree().process_frame
	_panel.bind(null, _bs, _ictl, _player)


func _body() -> Node:
	# The freshly-swapped body is the child not yet flushed by queue_free (the
	# previous body lingers one frame as queued-for-deletion).
	var slot := _panel.get_node("Margin/VBox/BodySlot")
	for c in slot.get_children():
		if not c.is_queued_for_deletion():
			return c
	return null


# ── body scenes load intact (UID-strip guard) ──────────────────────────────

func test_every_body_scene_instances_with_script() -> void:
	for key in _BODY_SCENES:
		var scene: PackedScene = load(_BODY_SCENES[key])
		assert_not_null(scene, "%s body scene should load" % key)
		var body := scene.instantiate()
		add_child_autofree(body)
		await get_tree().process_frame
		assert_true(body is ContextBodyBase,
				"%s body must carry its ContextBodyBase script (UID intact)" % key)


# ── priority resolver ──────────────────────────────────────────────────────

func test_idle_body_when_nothing_active() -> void:
	assert_true(_body() is IdleBody, "no plan / core-move / pin → IdleBody")


func test_core_move_body_when_targeting() -> void:
	_ictl._move_targeting_source = _node
	_panel._on_context_changed()
	assert_true(_body() is CoreMoveBody, "core-move targeting → CoreMoveBody")


func test_pinned_body_when_pinned() -> void:
	_panel._on_node_pinned(_node)
	assert_true(_body() is PinnedNodeBody, "a pinned node → PinnedNodeBody")


func test_attack_body_outranks_pin_and_core() -> void:
	_panel._on_node_pinned(_node)
	_ictl._move_targeting_source = _node
	var plan := MeleeAttackPlan.new()
	plan.attacker = _player
	_bs.attack_plan = plan
	_panel._on_context_changed()
	assert_true(_body() is AttackPlanBody, "active attack plan wins the panel")


func test_pin_returns_after_higher_context_clears() -> void:
	_panel._on_node_pinned(_node)
	var plan := MeleeAttackPlan.new()
	plan.attacker = _player
	_bs.attack_plan = plan
	_panel._on_context_changed()
	assert_true(_body() is AttackPlanBody, "attack overrides the pin")
	_bs.attack_plan = null
	_panel._on_context_changed()
	assert_true(_body() is PinnedNodeBody, "pin persists and returns when attack clears")
