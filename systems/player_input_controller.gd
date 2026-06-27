class_name PlayerInputController
extends Node

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
## unpinned (null). The ContextPanel surfaces the pinned node's details.
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

## Core-move drag state (#21). `_core_drag_started` flips once the cursor leaves
## the core past CORE_DRAG_THRESHOLD; `_core_drag_landing` is the currently
## snapped landing (committed on release). Ghost + badge are lazily built.
var _core_drag_started := false
var _core_drag_landing: SkillNode = null
var _core_ghost: Control = null
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


func _on_node_added(skill_node: SkillNode) -> void:
	if not skill_node.left_clicked.is_connected(_on_skill_node_left_clicked):
		skill_node.left_clicked.connect(_on_skill_node_left_clicked)
	if not skill_node.right_clicked.is_connected(_on_skill_node_right_clicked):
		skill_node.right_clicked.connect(_on_skill_node_right_clicked)


func _on_skill_node_left_clicked(skill_node: SkillNode) -> void:
	if _route_battle_click(skill_node, true):
		return
	if _route_core_move_click(skill_node):
		return
	# Allocate channel: bare left-click on an unowned node. allocate() enforces
	# SP + adjacency; deallocation is the `D`-on-hover channel, not a click.
	if _is_players_turn() and skill_node.owned_by == null:
		allocation_system.allocate(skill_node, player)


func _on_skill_node_right_clicked(skill_node: SkillNode) -> void:
	# Right-click feeds the active attack plan first (melee pivot / magic source).
	# When no plan claims it, right-click toggles the node's pin in the context
	# panel — re-pinning the same node unpins it.
	if _route_battle_click(skill_node, false):
		return
	_set_pinned(null if skill_node == _pinned_node else skill_node)


func _set_pinned(node: SkillNode) -> void:
	if _pinned_node == node:
		return
	_pinned_node = node
	node_pinned.emit(node)


func _on_skill_node_hovered(skill_node: SkillNode) -> void:
	_hovered_node = skill_node


func _on_skill_node_unhovered() -> void:
	_hovered_node = null


## Two channels live here:
##  - Core-move DRAG (#21): once targeting is active (the player pressed their
##    own core), dragging the held mouse snaps a ghost core to the nearest
##    reachable landing and a hop badge floats by the cursor; release commits.
##    Click-to-move still works untouched — drag is the layered accelerator.
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
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if (event as InputEventKey).physical_keycode != _DEALLOC_KEY:
		return
	if not _is_players_turn() or _hovered_node == null:
		return
	if _hovered_node.owned_by == player:
		if allocation_system.deallocate(_hovered_node, player):
			get_viewport().set_input_as_handled()


func _is_players_turn() -> bool:
	return player != null and turn_manager != null \
			and turn_manager.current_entity == player


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
		plan._on_node_right_clicked(skill_node)
	return true


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
	if landing != null:
		var hops := maxi(0, allocation_system.core_path(player, landing).size() - 1)
		var mp := _movement_points_current()
		_center_ghost_at(landing.global_position)
		_core_ghost.modulate.a = 0.85
		_core_badge.text = "%d hop%s · %d MP left" % [hops, "" if hops == 1 else "s", maxi(0, mp - hops)]
	else:
		_center_ghost_at(world)
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
	return int(mp.current) if mp != null else 0


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


## Center the ghost star on a world point. The ghost is a Label (parented to a
## Node2D), and a Control positions by its top-left corner — so a bare
## `global_position = center` renders the glyph down-and-right of the node (the
## #21 "sits at bottom-right" report). Snap to minimum size, then offset by half.
func _center_ghost_at(world: Vector2) -> void:
	_core_ghost.reset_size()
	_core_ghost.global_position = world - _core_ghost.size * 0.5


func _ensure_core_drag_visuals() -> void:
	if _core_ghost == null:
		_core_ghost = Label.new()
		_core_ghost.text = "⭐"
		_core_ghost.add_theme_font_size_override("font_size", 40)
		_core_ghost.z_index = 100
		graph.add_child(_core_ghost)
	if _core_badge == null:
		_core_badge = Label.new()
		_core_badge.add_theme_font_size_override("font_size", 18)
		_core_badge.z_index = 100
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
	return mp != null and mp.current >= 1


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
	if player == value:
		return
	if player != null and player.stat_board != null:
		var prev_ap: PoolStat = player.stat_board.action_points
		if prev_ap != null and prev_ap.current_changed.is_connected(_on_ap_changed):
			prev_ap.current_changed.disconnect(_on_ap_changed)
	player = value
	if player != null and player.stat_board != null:
		var ap: PoolStat = player.stat_board.action_points
		if ap != null:
			ap.current_changed.connect(_on_ap_changed)


func _on_ap_changed(_new_current: Variant) -> void:
	_emit_gate_changed()
