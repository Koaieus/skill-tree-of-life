extends GutTest

## HighlightController: single active provider, priority resolver (attack plan >
## core-move > none), and the state_changed rebind that lets internal provider
## mutations repaint without a swap.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _player: Entity
var _nodes: Array[SkillNode]
var _ctl: HighlightController


func before_each() -> void:
	_graph = Graph.new()
	_graph.skill_nodes_container = Node2D.new()
	_graph.add_child(_graph.skill_nodes_container)
	_graph.edges_container = Node2D.new()
	_graph.add_child(_graph.edges_container)
	add_child_autofree(_graph)

	_nodes = []
	for i in 2:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	var e := Edge.new()
	e.from = _nodes[0]
	e.to = _nodes[1]
	_graph.edges_container.add_child(e)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_player = autofree(Entity.new())
	_player.stat_board = _BOARD.duplicate(true) as StatBoard
	_graph.add_child(_player)
	await get_tree().process_frame
	for n in _nodes:
		n.owned_by = _player
	_player.core_location = _nodes[0]
	_player.stat_board.movement_points.current = 1.0

	_ctl = autofree(HighlightController.new())
	_ctl.allocation_system = _alloc
	_ctl.graph = _graph
	_ctl.player = _player
	# Note: battle_system / input_ctl injected per-test; we drive _resolve()
	# directly rather than via _ready signal wiring.


func _make_plan() -> AttackPlan:
	var plan := MeleeAttackPlan.new()
	plan.attacker = _player
	return plan


# ── priority resolver ──────────────────────────────────────────────────────

func test_resolve_none_when_idle() -> void:
	_ctl._resolve()
	assert_null(_ctl.provider, "no attack plan + no core-move → no provider")


func test_resolve_core_move_when_targeting() -> void:
	var ictl: PlayerInputController = autofree(PlayerInputController.new())
	ictl._move_targeting_source = _nodes[0]  # pretend the player picked their core
	_ctl.input_ctl = ictl
	_ctl._resolve()
	assert_true(_ctl.provider is CoreMoveHighlightProvider,
			"core-move targeting active → core provider")


func test_attack_plan_node_role_survives_rename() -> void:
	# Guard the get_highlight_role→get_node_role migration: an attack plan, used
	# as a HighlightProvider, must still report ORIGIN for its source. If this
	# breaks, combat highlights silently stop painting (no error, boots fine).
	var plan := _make_plan()
	plan.source = _nodes[0]
	var provider: HighlightProvider = plan
	assert_eq(provider.get_node_role(_nodes[0]), HighlightProvider.HighlightRole.ORIGIN,
			"melee plan's pivot is ORIGIN through the HighlightProvider interface")


func test_attack_plan_outranks_core_move() -> void:
	var ictl: PlayerInputController = autofree(PlayerInputController.new())
	ictl._move_targeting_source = _nodes[0]
	_ctl.input_ctl = ictl
	var bs: BattleSystem = autofree(BattleSystem.new())
	bs.attack_plan = _make_plan()
	_ctl.battle_system = bs
	_ctl._resolve()
	assert_true(_ctl.provider is MeleeAttackPlan,
			"an active attack plan wins over core-move targeting")


# ── state_changed rebind ───────────────────────────────────────────────────

func test_provider_changed_emits_on_swap() -> void:
	watch_signals(_ctl)
	var plan := _make_plan()
	_ctl.provider = plan
	assert_signal_emitted(_ctl, "provider_changed")


func test_state_changed_rebinds_across_swap() -> void:
	var plan := _make_plan()
	_ctl.provider = plan
	watch_signals(_ctl)
	plan.state_changed.emit()
	assert_signal_emit_count(_ctl, "provider_state_changed", 1,
			"active provider's mutation re-emits as provider_state_changed")
	# Swap away — the old provider's signal must no longer drive repaints.
	_ctl.provider = null
	plan.state_changed.emit()
	assert_signal_emit_count(_ctl, "provider_state_changed", 1,
			"a detached provider's state_changed is ignored after the swap")
