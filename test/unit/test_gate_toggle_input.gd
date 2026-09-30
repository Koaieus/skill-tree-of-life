extends GutTest

## Gate toggle input (#1206): the bulk actions expand the seat-local lock set
## into one ToggleGatesCommand, a stranding flip arms a one-warning confirm, a
## span click toggles one gate, and locks are kept per entity.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _battle: BattleSystem
var _tm: TurnManager
var _ctl: PlayerInputController
var _applier: CommandApplier
var _me: Entity
var _other: Entity
var _nodes: Dictionary
var _submitted: Array[ToggleGatesCommand] = []
var _ad: Gate  # A–D, open, toggleable
var _be: Gate  # B–E, closed, toggleable
var _cf: Gate  # C–F, closed, frozen (F is Other's)


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_nodes = {}
	for id in ["A", "B", "C", "D", "E", "F", "S"]:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = id
		_graph.add_skill_node(sn)
		_nodes[id] = sn
	_graph.add_edge(_n("A"), _n("B"))
	_graph.add_edge(_n("B"), _n("C"))

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	_alloc.navigator = _graph.navigator
	add_child_autofree(_alloc)
	_battle = autofree(BattleSystem.new())
	add_child(_battle)
	_tm = autofree(TurnManager.new())
	add_child(_tm)

	_me = _entity("Me")
	_other = _entity("Other")
	await get_tree().process_frame
	_me.core_location = _n("A")
	for id in ["A", "B", "C"]:
		_alloc.force_allocate(_me, _n(id))
	_other.core_location = _n("F")
	_alloc.force_allocate(_other, _n("F"))

	_ad = _graph.add_gate(_n("A"), _n("D"), true)
	_be = _graph.add_gate(_n("B"), _n("E"), false)
	_cf = _graph.add_gate(_n("C"), _n("F"), false)

	_tm.start_turn(_me)

	_applier = CommandApplier.new()
	_applier.graph = _graph
	_applier.allocation_system = _alloc
	_applier.battle_system = _battle
	_applier.turn_manager = _tm
	add_child_autofree(_applier)
	_submitted = []
	_applier.command_applied.connect(func(c: Command, _ok: bool):
		if c is ToggleGatesCommand:
			_submitted.append(c))

	_ctl = PlayerInputController.new()
	_ctl.graph = _graph
	_ctl.allocation_system = _alloc
	_ctl.battle_system = _battle
	_ctl.turn_manager = _tm
	_ctl.command_applier = _applier
	_ctl.player = _me
	add_child_autofree(_ctl)


func _entity(label: String) -> Entity:
	var e: Entity = autofree(Entity.new())
	e.display_name = label
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(e)
	return e


func _n(id: String) -> SkillNode:
	return _nodes[id]


## The gates a command names, as sorted "X-Y" labels (direction-free).
func _named(cmd: ToggleGatesCommand) -> Array[String]:
	var out: Array[String] = []
	for i in range(0, cmd.pairs.size(), 2):
		var a := String(_graph.get_by_stable_id(cmd.pairs[i]).name)
		var b := String(_graph.get_by_stable_id(cmd.pairs[i + 1]).name)
		var ab := [a, b]
		ab.sort()
		out.append("%s-%s" % ab)
	out.sort()
	return out


# ── Acceptance 1: toggle-all ────────────────────────────────────────────────

func test_toggle_unlocked_submits_one_command_naming_every_toggleable_gate() -> void:
	_ctl.request_gate_action(PlayerInputController.GateAction.TOGGLE_UNLOCKED)
	assert_eq(_submitted.size(), 1, "one command for the whole toggle")
	if _submitted.size() == 1:
		assert_eq(_named(_submitted[0]), ["A-D", "B-E"] as Array[String],
				"every toggleable gate, the frozen C–F skipped")
	assert_true(_ctl.pending_gate_strand().is_empty(), "nothing stranded, nothing armed")


func test_stranding_toggle_arms_on_first_press_and_submits_on_second() -> void:
	_alloc.force_allocate(_me, _n("D"))  # D hangs off the core only via A–D
	var armed: Array = []
	_ctl.gate_confirm_changed.connect(func(s): armed.append(s))
	_ctl.request_gate_action(PlayerInputController.GateAction.TOGGLE_UNLOCKED)
	assert_eq(_submitted.size(), 0, "first press submits nothing")
	assert_eq(_ctl.pending_gate_strand(), [_n("D")] as Array[SkillNode],
			"the stranded set is exposed")
	assert_eq(armed.size(), 1, "the confirm armed once")
	_ctl.request_gate_action(PlayerInputController.GateAction.TOGGLE_UNLOCKED)
	assert_eq(_submitted.size(), 1, "the identical second press submits")
	assert_true(_ctl.pending_gate_strand().is_empty(), "and disarms")


func test_a_different_request_disarms_the_confirm() -> void:
	_alloc.force_allocate(_me, _n("D"))
	_ctl.request_gate_action(PlayerInputController.GateAction.TOGGLE_UNLOCKED)
	_ctl.request_gate_action(PlayerInputController.GateAction.OPEN_UNLOCKED)
	assert_true(_ctl.pending_gate_strand().is_empty(), "another request disarms")
	assert_eq(_submitted.size(), 1, "open-all strands nothing, so it goes through")
	if _submitted.size() == 1:
		assert_eq(_named(_submitted[0]), ["B-E"] as Array[String])


func test_the_highlight_provider_reads_the_stranded_set() -> void:
	var provider := GateCutHighlightProvider.new()
	var stranded: Array[SkillNode] = [_n("D")]
	provider.stranded = stranded
	assert_eq(provider.get_node_role(_n("D")), HighlightProvider.HighlightRole.HOSTILE_TARGET)
	assert_eq(provider.get_node_role(_n("B")), HighlightProvider.HighlightRole.NONE)


# ── Acceptance 2: span click ────────────────────────────────────────────────

func test_span_click_toggles_that_one_gate_only() -> void:
	_ctl.route_gate_click(_be)
	assert_eq(_submitted.size(), 1)
	if _submitted.size() == 1:
		assert_eq(_named(_submitted[0]), ["B-E"] as Array[String])


func test_span_click_toggles_a_locked_gate_too() -> void:
	_ctl.toggle_gate_lock(_be)
	_ctl.route_gate_click(_be)
	assert_eq(_submitted.size(), 1, "a deliberate click ignores the lock")


func test_span_click_on_a_frozen_gate_submits_nothing() -> void:
	_ctl.route_gate_click(_cf)
	assert_eq(_submitted.size(), 0)


# ── Amendment: locks and bulk ───────────────────────────────────────────────

func test_toggle_unlocked_skips_locked_gates() -> void:
	_ctl.toggle_gate_lock(_ad)
	assert_true(_ctl.is_gate_locked(_ad))
	_ctl.request_gate_action(PlayerInputController.GateAction.TOGGLE_UNLOCKED)
	assert_eq(_submitted.size(), 1)
	if _submitted.size() == 1:
		assert_eq(_named(_submitted[0]), ["B-E"] as Array[String])


func test_open_all_and_close_all_skip_gates_already_in_that_state() -> void:
	_ctl.request_gate_action(PlayerInputController.GateAction.OPEN_UNLOCKED)
	_ctl.request_gate_action(PlayerInputController.GateAction.CLOSE_UNLOCKED)
	assert_eq(_submitted.size(), 2)
	if _submitted.size() == 2:
		assert_eq(_named(_submitted[0]), ["B-E"] as Array[String], "open-all: only the closed one")
		# B–E is open now; close-all takes both open unlocked gates.
		assert_eq(_named(_submitted[1]), ["A-D", "B-E"] as Array[String])


func test_open_all_with_everything_open_submits_nothing() -> void:
	_ctl.route_gate_click(_be)
	_submitted.clear()
	_ctl.request_gate_action(PlayerInputController.GateAction.OPEN_UNLOCKED)
	assert_eq(_submitted.size(), 0, "idempotent: no empty command")


func test_lock_all_and_unlock_all_submit_nothing() -> void:
	_ctl.request_gate_action(PlayerInputController.GateAction.LOCK_ALL)
	assert_true(_ctl.is_gate_locked(_ad) and _ctl.is_gate_locked(_be))
	_ctl.request_gate_action(PlayerInputController.GateAction.UNLOCK_ALL)
	assert_false(_ctl.is_gate_locked(_ad) or _ctl.is_gate_locked(_be))
	assert_eq(_submitted.size(), 0, "locks are input state, never a command")


func test_locks_hotkey_flips_between_unlock_all_and_lock_all() -> void:
	_ctl.request_gate_locks_hotkey()
	assert_true(_ctl.is_gate_locked(_ad) and _ctl.is_gate_locked(_be),
			"everything unlocked → lock all")
	_ctl.request_gate_locks_hotkey()
	assert_false(_ctl.is_gate_locked(_ad) or _ctl.is_gate_locked(_be),
			"anything locked → unlock all")
	_ctl.toggle_gate_lock(_ad)
	_ctl.request_gate_locks_hotkey()
	assert_false(_ctl.is_gate_locked(_ad), "one lock is enough to unlock all")


func test_locks_are_kept_per_entity_across_a_rebind() -> void:
	_ctl.toggle_gate_lock(_ad)
	_ctl.player = _other
	assert_false(_ctl.is_gate_locked(_ad), "the other seat has its own locks")
	_ctl.player = _me
	assert_true(_ctl.is_gate_locked(_ad), "and mine survive the handover")
