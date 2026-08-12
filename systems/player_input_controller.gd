class_name PlayerInputController
extends Node

const ZLayers = preload("res://ui/z_layers.gd")

## Routes player input (skill-node clicks + UI intent) on behalf of a single
## Player entity. There are no turn phases — intent is disambiguated by INPUT
## CHANNEL, and each channel is gated only by "is it this player's turn?" plus
## its own budget (SP / DP / AP / MP, all enforced inside the systems):
##
##   - Left-click an unowned node            → allocate (SP + adjacency)
##   - Hover a node + press `D`              → deallocate (DP, non-islanding)
##   - Left-click own core (no active attack)→ core-move targeting (#21)
##   - Attack / cast                         → AttackModeBar picks the mode,
##                                             then node clicks feed the plan
##                                             (left arms/resolves, right pops
##                                             one level — see
##                                             docs/design/click_grammar.md)
##
## Emits [signal player_can_act_changed] so UI can mirror enabled/disabled
## state (AP-driven now that phases are gone).
##
## A single-player handler is enough for the MVP. Multi-entity selection
## (per-entity cores, hot-seat) would replace `player` with a selection
## strategy without changing the dispatch shape.

## Physical key that triggers deallocate-on-hover. Not an InputMap action so it
## stays self-contained; promote to an action if rebinding is ever wanted.
const _DEALLOC_KEY := KEY_D

## Beat between hops when committing a multi-hop core move, so the slides read as
## a cascade. Slightly under SkillNode's slide duration (~0.25s).
const CORE_HOP_SLIDE_DELAY := 0.18

## Core-move drag (#21). Cursor must leave the core by this many world px before
## a press-hold counts as a drag (so a plain click still routes to click-to-move).
const CORE_DRAG_THRESHOLD := 10.0
## Max world distance from cursor to a landing for the ghost to snap onto it.
const CORE_DRAG_SNAP_RADIUS := 90.0

@export var graph: Graph
@export var allocation_system: AllocationSystem
@export var battle_system: BattleSystem
@export var player: Entity: set = _set_player
@export var turn_manager: TurnManager

signal player_can_act_changed(can_act: bool)
## Core-move targeting state (#21). `source` is the player's core node while a
## click-source-then-target move is in flight, or null when no move is being
## composed. Future highlight overlay subscribes here to paint CORE_LANDING /
## CORE_PATH roles.
signal core_move_targeting_changed(source: SkillNode)

## A node was pinned (right-clicked when no attack plan was eating the click) or
## unpinned (null). [NodeInspectorCard] surfaces the pinned node's details.
signal node_pinned(node: SkillNode)

## The player's core node while a click-to-move is in progress. Null between
## moves. Set only via `_set_move_targeting_source` so the signal fires once
## per transition.
var _move_targeting_source: SkillNode = null

## Node currently under the cursor, tracked via the Events hover bus so the
## `D`-to-deallocate channel knows what to act on. Null when nothing hovered.
var _hovered_node: SkillNode = null

## Node pinned to the context panel via right-click (when no attack plan claims
## the click). Null when nothing is pinned.
var _pinned_node: SkillNode = null

const _CORE_PRESENCE_SCENE := preload("res://skill_node/visuals/core_presence.tscn")

## Core-move drag state (#21, #128). `_core_drag_started` flips once the
## cursor leaves the core past CORE_DRAG_THRESHOLD; `_core_drag_landing` is the
## currently snapped landing (committed on release). Ghost + badge are lazily
## built. `_core_ghost` is a standalone CorePresence instance (same scene the
## live in-node one uses) — halo always shown, bloom shown only while snapped
## to a valid landing (see the locked #128 drag-ghost design).
var _core_drag_started := false
var _core_drag_landing: SkillNode = null
var _core_ghost: Node2D = null
var _core_badge: Label = null


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# `player` may be wired post-_ready (procgen sandboxes spawn it during
	# GameRoot._setup_level). Skip the player-dependent gate, not the graph
	# subscription — clicks still connect; routing checks player at fire time.
	if graph == null or allocation_system == null or turn_manager == null:
		push_warning("PlayerInputController missing graph/allocation/turn_manager; clicks won't route")
		return
	graph.node_added.connect(_on_node_added)
	for sn in graph.get_skill_nodes():
		_on_node_added(sn)

	turn_manager.turn_started.connect(_emit_gate_changed.unbind(1))
	turn_manager.turn_ended.connect(_emit_gate_changed.unbind(1))

	Events.skill_node_hovered.connect(_on_skill_node_hovered)
	Events.skill_node_unhovered.connect(_on_skill_node_unhovered)
	Events.node_action_denied.connect(_on_node_action_denied)

	if battle_system != null:
		battle_system.attack_plan_changed.connect(_update_cursor.unbind(1))
	core_move_targeting_changed.connect(_update_cursor.unbind(1))


func _on_node_added(skill_node: SkillNode) -> void:
	if not skill_node.left_clicked.is_connected(_on_skill_node_left_clicked):
		skill_node.left_clicked.connect(_on_skill_node_left_clicked)


func _on_skill_node_left_clicked(skill_node: SkillNode) -> void:
	if _route_battle_click(skill_node, true):
		return
	if _route_core_move_click(skill_node):
		return
	# Allocate channel: bare left-click on an unowned node. allocate() enforces
	# SP + adjacency; deallocation is the `D`-on-hover channel, not a click.
	if _is_players_turn() and skill_node.owned_by == null:
		allocation_system.allocate(skill_node, player)


func _set_pinned(node: SkillNode) -> void:
	if _pinned_node == node:
		return
	_pinned_node = node
	node_pinned.emit(node)


func _on_skill_node_hovered(skill_node: SkillNode) -> void:
	_hovered_node = skill_node


func _on_skill_node_unhovered() -> void:
	_hovered_node = null


## Channels live here:
##  - Core-move DRAG (#21): once targeting is active (the player pressed their
##    own core), dragging the held mouse snaps a ghost core to the nearest
##    reachable landing and a hop badge floats by the cursor; release commits.
##    Click-to-move still works untouched — drag is the layered accelerator.
##  - RIGHT-CLICK: pops one level off whichever mode is armed (attack plan or
##    core-move — docs/design/click_grammar.md), node-independent like Esc
##    (below). Handled here rather than via a per-`SkillNode` signal so it
##    fires over empty space too, not just when the cursor is over a node —
##    `SkillNode._on_input_event`'s physics picking runs a physics tick after
##    `_unhandled_input`, so routing the pop through a node signal would read
##    stale pre-pop armed-state on the very click that's popping it. When
##    nothing is armed, right-click instead toggles `_hovered_node`'s pin in
##    the context panel (re-pinning the same node unpins it) — this still
##    needs a node, so it silently no-ops over empty space.
##  - DEALLOCATE: pressing `D` while hovering one of the player's own non-core
##    nodes deallocates it (DP + non-islanding enforced in deallocate()).
func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseMotion:
		if _move_targeting_source != null and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_update_core_drag()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_on_core_drag_released()
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if _pop_armed_mode():
				get_viewport().set_input_as_handled()
			elif _hovered_node != null:
				_set_pinned(null if _hovered_node == _pinned_node else _hovered_node)
				get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if (event as InputEventKey).physical_keycode != _DEALLOC_KEY:
		return
	if not _is_players_turn() or _hovered_node == null:
		return
	# D is Manage's accelerator, not a global override — gated off while any
	# other targeting mode is armed so it can't deallocate mid-attack-plan-
	# selection or mid-core-move (#404).
	if _has_armed_mode():
		return
	if _hovered_node.owned_by == player:
		if allocation_system.deallocate(_hovered_node, player):
			get_viewport().set_input_as_handled()
		else:
			Events.node_action_denied.emit(_hovered_node, "deallocate_denied")
			get_viewport().set_input_as_handled()


## `ui_cancel` (Esc) aliases the same one-level pop right-click uses. Runs
## before [PauseMenu]'s `_unhandled_key_input` (Systems precedes UI in
## game_root.tscn's child order, and same-phase callbacks fire in tree order)
## so a non-empty stack pops instead of opening the pause menu; an empty
## stack leaves the event unhandled and PauseMenu toggles exactly as today.
func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event.is_action_pressed(&"ui_cancel") and _pop_armed_mode():
		get_viewport().set_input_as_handled()


func _is_players_turn() -> bool:
	return player != null and turn_manager != null \
			and turn_manager.current_entity == player


## Feedback for a node-targeted verb that was gated away (#89, generalized
## #404). If the reason is islanding, the nodes that would be cut off from the
## core pulse danger-red; the node the player actually tried to act on always
## gets a short "no" shake. Other denials (out of DP, core node) just shake
## the target — there's no "these get cut off" story to tell. Self-subscribed
## to [signal Events.node_action_denied] so any verb can trigger this, not
## just deallocate.
func _on_node_action_denied(node: SkillNode, _reason: String) -> void:
	if player != null and player.navigator != null and player.core_location != null:
		for islanded in player.navigator.nodes_islanded_by_removing(node, player.core_location):
			islanded.blink_blocked()
	node.shake_denied()


## Returns true if an active attack plan handled the click. Gating: player's
## turn AND the active plan belongs to this player. Caller treats `true`
## as "consumed, no further routing".
func _route_battle_click(skill_node: SkillNode, is_left: bool) -> bool:
	if not can_player_act():
		return false
	if not battle_system.is_attacking:
		return false
	var plan := battle_system.attack_plan
	if plan == null or plan.attacker != player:
		return false
	if is_left:
		plan._on_node_left_clicked(skill_node)
	else:
		# Right-click always affects the attack-mode stack while a plan is
		# armed — never falls through to pin-toggle. A pop with nothing left
		# to clear (mode armed, no origin) exits the mode entirely instead of
		# being swallowed silently. See docs/design/click_grammar.md.
		if not plan._on_node_right_clicked(skill_node):
			battle_system.cancel_attack()
	return true


## True if either an attack plan armed for this player, or core-move
## targeting, is currently active (#404). Single source of truth for "is
## anything armed right now" — gates the D-key channel and decides whether
## right-click / Esc pop a level instead of falling through to pin-toggle /
## PauseMenu.
func _has_armed_mode() -> bool:
	return _active_attack_plan() != null or _move_targeting_source != null


func _active_attack_plan() -> AttackPlan:
	if battle_system == null or battle_system.attack_plan == null:
		return null
	var plan := battle_system.attack_plan
	return plan if plan.attacker == player else null


## Node-independent stack-pop primitive shared by right-click and Esc (#404).
## Right-click "ignores which node was clicked"
## (docs/design/click_grammar.md), and Esc has no node at all, so this never
## takes one. Returns true if something was armed to pop/exit.
func _pop_armed_mode() -> bool:
	if can_player_act():
		var plan := _active_attack_plan()
		if plan != null:
			if not plan.pop():
				battle_system.cancel_attack()
			return true
	if _move_targeting_source != null:
		_set_move_targeting_source(null)
		return true
	return false


## Swaps the OS cursor while any targeting mode is armed (#404) — a plain
## shape swap, cleared on resolve/cancel. Separate from #412's viewport-wide
## armed-mode vignette (sequenced after this issue).
func _update_cursor() -> void:
	Input.set_default_cursor_shape(
			Input.CURSOR_CROSS if _has_armed_mode() else Input.CURSOR_ARROW)


## Core-movement (#21) click routing. Two clicks: first click on the player's
## own core enters targeting; second click on an adjacent owned node commits
## via `AllocationSystem.move_core`. Returns true when the click was consumed
## (don't fall through to allocate). Runs only when no attack plan is active —
## `_route_battle_click` takes precedence and already consumed the click if so.
##
## Rules:
##  - Not the player's turn, or zero MP → no-op, fall through. Active targeting
##    state is cleared so a stale source can't outlive its eligibility window.
##  - No source set + click on player.core_location → enter targeting.
##  - Source set + click on source → cancel targeting.
##  - Source set + click on any owned node → call move_core (succeeds for
##    adjacent, fails silently for non-adjacent) and clear targeting. Consumed
##    so a non-adjacent owned click can't fall through unexpectedly.
##  - Source set + click on unowned/enemy node → cancel targeting, fall through
##    so the player can still allocate.
func _route_core_move_click(skill_node: SkillNode) -> bool:
	if player == null or turn_manager == null or allocation_system == null:
		return false
	if turn_manager.current_entity != player:
		return false
	if not _player_has_movement_points():
		if _move_targeting_source != null:
			_set_move_targeting_source(null)
		return false

	if _move_targeting_source == null:
		if skill_node == player.core_location:
			_set_move_targeting_source(skill_node)
			return true
		return false

	# Targeting is active — this click is the target.
	if skill_node == _move_targeting_source:
		_set_move_targeting_source(null)
		return true
	if skill_node.owned_by == player:
		_commit_core_move(skill_node)
		_set_move_targeting_source(null)
		return true
	# Click on someone else's node / unowned: cancel and fall through so
	# allocate still works without a second click.
	_set_move_targeting_source(null)
	return false


## Public read of the active core-move source (the player's core while a
## click-to-move or drag is being composed), or null. Highlight providers read
## this to paint reachability.
func move_targeting_source() -> SkillNode:
	return _move_targeting_source


## Commit a core move to [param target] by hopping along the shortest owned-edge
## path one node at a time — each hop spends 1 MP and plays its slide. Adjacent
## target → a single `move_core`; reachable-but-distant target → walks the BFS
## path (`AllocationSystem.core_path`). Non-reachable / over-budget targets give
## an empty path and no-op. Awaits a beat between hops so the multi-hop slide
## reads as a cascade rather than one snap.
func _commit_core_move(target: SkillNode) -> void:
	var path := allocation_system.core_path(player, target)
	if path.size() < 2:
		return
	for i in range(1, path.size()):
		if not allocation_system.move_core(player, path[i]):
			break
		if i < path.size() - 1:
			await get_tree().create_timer(CORE_HOP_SLIDE_DELAY).timeout


## Mouse moved with the button held while core-move targeting is active: snap a
## ghost core to the nearest reachable landing under the cursor (within
## CORE_DRAG_SNAP_RADIUS) and float a hop badge. Pushes the snapped landing into
## the active highlight provider so the on-route preview brightens live.
func _update_core_drag() -> void:
	var src := _move_targeting_source
	if src == null or graph == null:
		return
	var world := graph.get_global_mouse_position()
	if not _core_drag_started:
		if world.distance_to(src.global_position) < CORE_DRAG_THRESHOLD:
			return  # still a click, not a drag
		_core_drag_started = true
		_ensure_core_drag_visuals()
	var landing := _nearest_reachable_landing(world)
	_core_drag_landing = landing
	# Bloom glyph joins the ghost only once snapped to a valid target (#128) —
	# the halo alone follows the cursor otherwise.
	_core_ghost.get_node(^"CoreSigilBloom").visible = landing != null
	if landing != null:
		var hops := maxi(0, allocation_system.core_path(player, landing).size() - 1)
		var mp := _movement_points_current()
		_core_ghost.global_position = landing.global_position
		_core_ghost.modulate.a = 0.85
		_core_badge.text = "%d hop%s · %d MP left" % [hops, "" if hops == 1 else "s", maxi(0, mp - hops)]
	else:
		_core_ghost.global_position = world
		_core_ghost.modulate.a = 0.4
		_core_badge.text = "—"
	_core_badge.global_position = world + Vector2(18, -10)
	_set_drag_preview_target(landing)


## Release while dragging commits to the snapped landing (multi-hop along the
## owned path) and ends targeting. A release without a real drag is left alone so
## click-to-move keeps working (next click is the landing).
func _on_core_drag_released() -> void:
	if not _core_drag_started:
		return
	var landing := _core_drag_landing
	_clear_core_drag()
	if landing != null and _move_targeting_source != null:
		_commit_core_move(landing)
	_set_move_targeting_source(null)


func _nearest_reachable_landing(world: Vector2) -> SkillNode:
	var src := _move_targeting_source
	if src == null or src.owned_by == null or allocation_system == null:
		return null
	var reach := allocation_system.reachable_core_landings(src.owned_by, _movement_points_current())
	var best: SkillNode = null
	var best_d := CORE_DRAG_SNAP_RADIUS
	for node in reach:
		var d: float = world.distance_to((node as SkillNode).global_position)
		if d < best_d:
			best_d = d
			best = node
	return best


func _movement_points_current() -> int:
	if player == null or player.stat_board == null:
		return 0
	var mp: PoolStat = player.stat_board.movement_points
	return mp.available() if mp != null else 0


## Mirror the drag's snapped landing into the active core-move highlight provider
## (if that's what's driving highlights right now) so the brightened target ring
## tracks the ghost. No-op when an attack plan owns the highlights.
func _set_drag_preview_target(landing: SkillNode) -> void:
	var ctl := get_tree().get_first_node_in_group(HighlightController.GROUP) as HighlightController
	if ctl == null:
		return
	var core_provider := ctl.active_core_provider()
	if core_provider != null:
		core_provider.set_target(landing)


## Builds the drag-ghost lazily: a standalone [CorePresence] instance (the
## same scene the live in-node core presence uses, #128) rather than the old
## hardcoded star Label. It's a Node2D, so it centers on a world point with a
## bare `global_position` assignment — no Control top-left correction needed.
func _ensure_core_drag_visuals() -> void:
	if _core_ghost == null:
		_core_ghost = _CORE_PRESENCE_SCENE.instantiate()
		_core_ghost.z_index = ZLayers.CORE_MOVE
		graph.add_child(_core_ghost)
		var tint := player.color if player != null else Color.WHITE
		var r := _move_targeting_source.radius if _move_targeting_source != null else 32.0
		var sigil: Sigil = null
		if player != null and player.core_class != null:
			sigil = player.core_class.sigil
		for child_name in [&"CoreHalos", &"CoreSigilBloom"]:
			var child := _core_ghost.get_node(NodePath(child_name)) as SkillNodeVisual
			child.entity_tint = tint
			child.radius = r
		_core_ghost.get_node(^"CoreHalos").visible = true
		var bloom := _core_ghost.get_node(^"CoreSigilBloom")
		bloom.sigil = sigil
		bloom.visible = false  # joins the ghost only once snapped to a target
	if _core_badge == null:
		_core_badge = Label.new()
		_core_badge.add_theme_font_size_override("font_size", 18)
		_core_badge.z_index = ZLayers.CORE_MOVE
		graph.add_child(_core_badge)
	_core_ghost.visible = true
	_core_badge.visible = true


func _clear_core_drag() -> void:
	_core_drag_started = false
	_core_drag_landing = null
	if _core_ghost != null:
		_core_ghost.queue_free()
		_core_ghost = null
	if _core_badge != null:
		_core_badge.queue_free()
		_core_badge = null


func _player_has_movement_points() -> bool:
	if player == null or player.stat_board == null:
		return false
	var mp: PoolStat = player.stat_board.movement_points
	return mp != null and mp.available() >= 1


func _set_move_targeting_source(value: SkillNode) -> void:
	if _move_targeting_source == value:
		return
	_move_targeting_source = value
	if value == null:
		_clear_core_drag()
	core_move_targeting_changed.emit(value)


func can_player_act() -> bool:
	if not _is_players_turn():
		return false
	# AP=0 blocks further attack/cast actions; UI uses this to dim.
	if player != null and player.stat_board != null:
		var ap: PoolStat = player.stat_board.action_points
		if ap != null and ap.current <= 0:
			return false
	return true


func on_attack_mode_requested(mode: BattleSystem.AttackMode) -> void:
	if can_player_act():
		battle_system.request_attack_mode(mode)


func _emit_gate_changed() -> void:
	player_can_act_changed.emit(can_player_act())


func _set_player(value: Entity) -> void:
	if player != null and player.stat_board != null:
		var prev_ap: PoolStat = player.stat_board.action_points
		if prev_ap != null and prev_ap.current_changed.is_connected(_on_ap_changed):
			prev_ap.current_changed.disconnect(_on_ap_changed)
	player = value
	if player != null and player.stat_board != null:
		var ap: PoolStat = player.stat_board.action_points
		if ap != null and not ap.current_changed.is_connected(_on_ap_changed):
			ap.current_changed.connect(_on_ap_changed)


func _on_ap_changed(_new_current: Variant) -> void:
	_emit_gate_changed()
