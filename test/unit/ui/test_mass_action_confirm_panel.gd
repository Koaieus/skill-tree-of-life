extends GutTest

## MassActionConfirmPanel — the mass allocate-path / deallocate-cascade confirm,
## ported off `get_tree().paused` onto [ModalBase]'s input freeze (#486).
## Mirrors test_loot_picker.gd: instantiate the real scene (which also proves
## the inherited-scene + [ModalBodyBase] wiring loads at all — `mise run check`
## compiles scripts, it does not instantiate scenes) and drive it like the
## player would.
##
## The case that matters most is the THIRD exit: a pending request cleared from
## outside the modal must still unfreeze input, or the player is left with a
## dead board and no way back.

const _PANEL_SCENE := preload("res://ui/mass_action_confirm/mass_action_confirm_panel.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _panel: MassActionConfirmPanel
var _ctl: PlayerInputController
var _graph: Graph
var _player: Entity
var _nodes: Array[SkillNode] = []


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)
	_nodes = []
	for i in 4:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.add_skill_node(sn)
		_nodes.append(sn)

	_player = autofree(Entity.new())
	_player.display_name = "Player"
	_player.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(_player)

	# No CommandApplier: confirm is only asked to REACH the controller here —
	# that the controller then applies the right command is
	# test/unit/systems/test_mass_action_input.gd's job.
	_ctl = autofree(PlayerInputController.new())
	_ctl.graph = _graph
	_ctl.player = _player
	add_child(_ctl)

	_panel = _PANEL_SCENE.instantiate()
	add_child_autofree(_panel)
	_panel.bind_systems(_ctl, null)


func _body() -> MassActionConfirmBody:
	return _panel._body as MassActionConfirmBody


## The panel guards `present()` against a request that is no longer pending, so
## every test has to actually arm one on the controller first.
func _allocate_request(affordable: int) -> MassActionRequest:
	var req := MassActionRequest.new(_player, MassActionRequest.Verb.ALLOCATE, _nodes)
	req.affordable_count = affordable
	_ctl._mass_action_request = req
	return req


func test_present_lists_every_node_but_the_frontier_anchor() -> void:
	_panel.present(_allocate_request(3))
	assert_true(_panel.visible, "panel shows on present")
	# nodes[0] is the already-owned anchor; 3 blocks + 3 separators for the rest.
	assert_eq(_body()._node_list.get_child_count(), 6, "one block + rule per allocated node")


func test_present_freezes_player_input() -> void:
	_panel.present(_allocate_request(3))
	assert_true(_ctl._input_frozen, "input frozen for the duration of the confirm")
	assert_false(get_tree().paused, "the SceneTree itself is never paused")


func test_confirm_is_dimmed_when_nothing_is_affordable() -> void:
	_panel.present(_allocate_request(0))
	assert_true(_panel._confirm_button.disabled, "0 affordable nodes buys nothing")


func test_confirm_button_takes_the_verb_as_its_label() -> void:
	_panel.present(_allocate_request(2))
	assert_eq(_panel._confirm_button.text, "ALLOCATE", "the body names the verb")


func test_confirm_executes_and_clears_the_pending_request() -> void:
	_panel.present(_allocate_request(2))
	_panel._on_confirm()
	assert_false(_panel.visible, "panel closes on confirm")
	assert_false(_ctl._input_frozen, "input unfrozen on confirm")
	assert_null(_ctl.pending_mass_action(), "the controller consumed the request")


func test_cancel_refuses_the_request() -> void:
	var req := _allocate_request(2)
	_panel.present(req)
	_panel._on_cancel()
	assert_false(_panel.visible, "panel closes on cancel")
	assert_false(_ctl._input_frozen, "input unfrozen on cancel")
	assert_null(_ctl.pending_mass_action(), "the request was dropped, not executed")


## The third exit: `clear_transient_state` (level teardown) drops the pending
## request. HudRoot turns that into `dismiss()` — which must unfreeze, or the
## next level starts with input latched off.
func test_dismiss_from_outside_unfreezes_and_closes() -> void:
	_panel.present(_allocate_request(2))
	_panel.dismiss()
	assert_false(_panel.visible, "panel closes when the request is revoked")
	assert_false(_ctl._input_frozen, "input unfrozen even with nothing answered")


func test_dismiss_is_a_no_op_when_not_showing() -> void:
	_ctl.set_input_frozen(true)
	_panel.dismiss()
	assert_true(_ctl._input_frozen, "a hidden modal never touches the freeze")


## `closed` is what drains HudRoot's modal queue — every exit must emit it
## exactly once, or the next modal is queued forever.
func test_every_exit_emits_closed() -> void:
	var closes: Array = []
	_panel.closed.connect(func() -> void: closes.append(true))
	_panel.present(_allocate_request(2))
	_panel._on_confirm()
	assert_eq(closes.size(), 1, "confirm closes")
	_panel.present(_allocate_request(2))
	_panel._on_cancel()
	assert_eq(closes.size(), 2, "cancel closes")
	_panel.present(_allocate_request(2))
	_panel.dismiss()
	assert_eq(closes.size(), 3, "an outside revoke closes")


func test_a_stale_request_closes_instead_of_presenting() -> void:
	var stale := MassActionRequest.new(_player, MassActionRequest.Verb.ALLOCATE, _nodes)
	var closes: Array = []
	_panel.closed.connect(func() -> void: closes.append(true))
	_panel.present(stale)
	assert_false(_panel.visible, "a request the controller no longer holds is dead")
	assert_eq(closes.size(), 1, "and still drains the queue")


## The inherited scene overrides Title/Subtitle by NODE PATH, and a stale path
## is a silently dropped override rather than a load failure — every other test
## here reads `%`-unique nodes, which resolve either way. `present()` rewrites
## the title text, so pin the styling the scene authored around it.
func test_the_inherited_scene_overrides_actually_applied() -> void:
	assert_eq(_panel._title.get_theme_font_size("font_size"), 24,
			"the confirm's title is a size smaller than a picker's")
	assert_eq(_panel._subtitle.autowrap_mode, TextServer.AUTOWRAP_WORD,
			"the 'reaches N of M' line has to wrap")
	assert_true(_panel._cancel_button.visible, "a mass action is refusable")


## Esc and right-click both back out. They ride `_input`, not
## `_unhandled_input`: the full-screen Dim is MOUSE_FILTER_STOP, so a mouse
## button never reaches the unhandled phase.
func test_escape_cancels() -> void:
	_panel.present(_allocate_request(2))
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	_panel._input(esc)
	assert_false(_panel.visible, "Esc refuses the request")
	assert_null(_ctl.pending_mass_action(), "and clears it")


func test_right_click_cancels() -> void:
	_panel.present(_allocate_request(2))
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true
	_panel._input(rmb)
	assert_false(_panel.visible, "right-click refuses the request")


## The loot pickers are must-answer: the same gestures do nothing there.
func test_a_non_cancellable_modal_ignores_the_back_out_gestures() -> void:
	_panel.cancellable = false
	_panel.present(_allocate_request(2))
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true
	_panel._input(rmb)
	assert_true(_panel.visible, "nothing to back out of when there's no Cancel")
