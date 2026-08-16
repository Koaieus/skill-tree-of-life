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

## Which temp upgrade (a MeleeAttackPlan.TEMP_UPGRADE_CATALOG entry) is armed
## for placement via the command-tray card, or null when unarmed (#406).
## Set only via `_set_temp_upgrade_arm` so the signal fires once per
## transition.
signal temp_upgrade_arm_changed(upgrade: Variant)
var _temp_upgrade_arm: Variant = null

## Manage-tab verbs (#338), armed via CommandTray's ManageBody cards through
## the #404 shared dispatcher. ALLOCATE mirrors the always-on bare-click
## fallback (arming it is cosmetic — cursor + card affordance only, no new
## click routing); DEALLOCATE/STAKE/EXTRACT resolve through
## [method _route_manage_click]. Move Core has no verb of its own — its card
## calls [method enter_core_move_targeting], reusing CoreMoveArmedMode.
enum ManageVerb { NONE, ALLOCATE, DEALLOCATE, STAKE, EXTRACT }
signal manage_arm_changed(verb: ManageVerb)
var _manage_arm: ManageVerb = ManageVerb.NONE

## A distant-allocate-path or would-island-deallocate click is pending
## confirmation (see MassActionRequest, MassActionArmedMode). Null when
## nothing is pending. Set only via `begin_mass_action`/`cancel_mass_action`/
## `confirm_mass_action` so the signal fires once per transition.
signal mass_action_pending_changed(request: MassActionRequest)
var _mass_action_request: MassActionRequest = null

## Ordered pop stack (#404's shared arm/pop primitive, generalized #406).
## Earlier entries pop before later ones — TempUpgradeArmedMode is checked
## first because it nests inside an already-armed attack plan and must pop
## before the plan does. Populated in _ready().
var _armed_modes: Array[ArmedMode] = []

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

	_armed_modes = [
		MassActionArmedMode.new(self),
		TempUpgradeArmedMode.new(self),
		AttackPlanArmedMode.new(self),
		CoreMoveArmedMode.new(self),
		ManageArmedMode.new(self),
	]

	if battle_system != null:
		battle_system.attack_plan_changed.connect(_update_cursor.unbind(1))
		# The arm can't outlive its plan (#406) — a plan swap or clear always
		# invalidates whatever temp-upgrade card was armed for the old one.
		battle_system.attack_plan_changed.connect(func(_p): _set_temp_upgrade_arm(null))
		# can_player_act() now also reads battle_system.is_launching (#406),
		# whose transitions have no signal of their own. attack_plan_changed
		# fires when a swing's post-await _reset() clears the plan — the only
		# observable moment is_launching flips back false — so AttackModeBar
		# (gated purely off player_can_act_changed, command_tray.gd) doesn't
		# stay disabled forever after the first swing of a turn.
		battle_system.attack_plan_changed.connect(_emit_gate_changed.unbind(1))
	core_move_targeting_changed.connect(_update_cursor.unbind(1))


func _on_node_added(skill_node: SkillNode) -> void:
	if not skill_node.left_clicked.is_connected(_on_skill_node_left_clicked):
		skill_node.left_clicked.connect(_on_skill_node_left_clicked)


func _on_skill_node_left_clicked(skill_node: SkillNode) -> void:
	if _mass_action_request != null:
		return
	if _route_temp_upgrade_click(skill_node):
		return
	if _route_battle_click(skill_node, true):
		return
	if _route_manage_click(skill_node):
		return
	if _route_core_move_click(skill_node):
		return
	# Allocate channel: bare left-click on an unowned node (first allocation)
	# or a player-owned node with cap headroom from a stake (refill, #337).
	# allocate() enforces SP + adjacency; deallocation is the `D`-on-hover
	# channel, not a click.
	if not _is_players_turn():
		return
	if skill_node.owned_by == player and skill_node.allocation_level < skill_node.stake_level:
		allocation_system.allocate(skill_node, player)
		return
	if skill_node.owned_by != null:
		return
	if allocation_system.can_allocate(skill_node, player):
		allocation_system.allocate(skill_node, player)
		return
	_try_begin_mass_allocate(skill_node)


## The bare-click fell through can_allocate — usually because [param target] is
## unowned but not adjacent to the player's territory. Route it through the
## multi-hop confirm flow (#... mass-action) instead of the old silent no-op.
## Denies outright (closing that gap) when there's no route, no SP at all, or
## the target is already owned/refillable (those are handled above and never
## reach here).
func _try_begin_mass_allocate(target: SkillNode) -> void:
	var available_sp := _skill_points_available()
	if available_sp < 1:
		Events.node_action_denied.emit(target, "allocate_denied_unreachable")
		return
	var path := allocation_system.allocation_path(player, target)
	if path.size() < 2:
		Events.node_action_denied.emit(target, "allocate_denied_unreachable")
		return
	var affordable: int = mini(path.size() - 1, available_sp)
	var request := MassActionRequest.new(player, MassActionRequest.Verb.ALLOCATE, path)
	request.affordable_count = affordable
	request.target = target
	begin_mass_action(request)


func _skill_points_available() -> int:
	if player == null or player.stat_board == null:
		return 0
	var sp: PoolStat = player.stat_board.skill_points
	return sp.available() if sp != null else 0


## Resolves an armed Manage verb (#338, via #404). STAKE/EXTRACT/DEALLOCATE
## consume the click whether they succeed or not (denial feedback fires on
## failure); ALLOCATE and NONE fall through so the existing core-move /
## bare-allocate routing below still runs unarmed. Must run BEFORE
## _route_core_move_click — staking/extracting the core itself (0 hops still
## counts as "within 1 hop") must not be swallowed by core-move targeting.
func _route_manage_click(skill_node: SkillNode) -> bool:
	if not _is_players_turn():
		return false
	match _manage_arm:
		ManageVerb.STAKE:
			_resolve_stake(skill_node)
			return true
		ManageVerb.EXTRACT:
			_resolve_extract(skill_node)
			return true
		ManageVerb.DEALLOCATE:
			_resolve_deallocate(skill_node)
			return true
	return false


## Shared deallocate verb call (#338) — both the `D`-hover accelerator and an
## armed-Deallocate click resolve through this. Unlike the `D` channel (which
## pre-gates on `owned_by == player` and stays silent otherwise, see
## _unhandled_input), this always fires denial feedback on failure — an
## explicit click on an illegal node while armed is a deliberate attempt, not
## an idle hover.
func _resolve_deallocate(node: SkillNode) -> bool:
	if allocation_system.deallocate(node, player):
		return true
	# would_disconnect_from rejected a plain deallocate — if that's the only
	# reason (the node is genuinely player's, non-core), offer the full
	# cascade via the confirm panel instead of a flat reject, regardless of
	# whether the player can currently afford it (Confirm just stays disabled
	# in that case — see docs/domain mass-action confirm panel).
	var cascade := allocation_system.deallocation_cascade(node, player)
	if cascade.size() > 1:
		var request := MassActionRequest.new(player, MassActionRequest.Verb.DEALLOCATE, cascade)
		begin_mass_action(request)
		return true
	Events.node_action_denied.emit(node, "deallocate_denied")
	return false


func _resolve_stake(node: SkillNode) -> bool:
	if allocation_system.stake(node, player):
		return true
	Events.node_action_denied.emit(node, _stake_denial_reason(node))
	return false


func _resolve_extract(node: SkillNode) -> bool:
	if allocation_system.extract(node, player):
		return true
	Events.node_action_denied.emit(node, _extract_denial_reason(node))
	return false


## Re-derives why `can_stake` rejected [param node] as a reason string.
## AllocationSystem.can_stake only returns a bool (#338 doesn't touch
## allocation_system.gd), so the gate order here must mirror can_stake's.
func _stake_denial_reason(node: SkillNode) -> String:
	if node == null or node.owned_by != player:
		return "stake_denied_not_owned"
	if node.stake_level >= AllocationSystem.STAKE_CEILING:
		return "stake_denied_at_ceiling"
	if not _core_within_one_hop(node):
		return "stake_denied_not_adjacent"
	var board := player.stat_board if player != null else null
	if board != null and board.skill_points != null and board.skill_points.available() < 1:
		return "stake_denied_no_sp"
	if board != null and board.action_points != null and board.action_points.available() < 1:
		return "stake_denied_no_ap"
	return "stake_denied"


## Mirrors can_extract's gate order — see _stake_denial_reason.
func _extract_denial_reason(node: SkillNode) -> String:
	if node == null or node.owned_by != player:
		return "extract_denied_not_owned"
	if node.stake_level <= 1:
		return "extract_denied_at_floor"
	if not _core_within_one_hop(node):
		return "extract_denied_not_adjacent"
	var board := player.stat_board if player != null else null
	if board != null and board.deallocation_points != null and board.deallocation_points.available() < 1:
		return "extract_denied_no_dp"
	if board != null and board.skill_points != null and board.skill_points.staked < 1:
		return "extract_denied_no_staked_sp"
	return "extract_denied"


## Same "core within 1 hop over the owned subgraph" check as
## AllocationSystem._core_within_one_hop, bound to `player` — duplicated
## rather than reaching into that private helper.
func _core_within_one_hop(node: SkillNode) -> bool:
	if player == null or player.navigator == null or player.core_location == null:
		return false
	return player.navigator.nodes_within(player.core_location, 1).has(node)


## Resolves an armed temp-upgrade placement (#406) — click-to-toggle, same
## shape as blade-member selection: clicking a node that already carries
## this exact temp upgrade refunds it, clicking any other eligible node
## applies a new one. Stays armed either way — apply's own gating already
## makes a failed attempt fail gracefully with denial feedback, so there's
## no correctness reason to force a re-click of the tray button per action.
## Must run BEFORE _route_battle_click, which would otherwise claim the click
## for blade-membership toggling.
func _route_temp_upgrade_click(skill_node: SkillNode) -> bool:
	if _temp_upgrade_arm == null or not can_player_act():
		return false
	var plan := _active_attack_plan() as MeleeAttackPlan
	if plan == null:
		return false
	if plan.toggle_temp_upgrade(skill_node, _temp_upgrade_arm):
		return true
	var reason := "temp_upgrade_denied_slot_full" \
			if not skill_node.can_attach_addon(_temp_upgrade_arm.script) \
			else "temp_upgrade_denied_budget"
	Events.node_action_denied.emit(skill_node, reason)
	return true


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
		_resolve_deallocate(_hovered_node)
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


## True if any level of the armed-mode stack (#404, generalized #406 —
## _armed_modes) is currently active. Single source of truth for "is
## anything armed right now" — gates the D-key channel and decides whether
## right-click / Esc pop a level instead of falling through to pin-toggle /
## PauseMenu.
func _has_armed_mode() -> bool:
	for m in _armed_modes:
		if m.is_armed():
			return true
	return false


func _active_attack_plan() -> AttackPlan:
	if battle_system == null or battle_system.attack_plan == null:
		return null
	var plan := battle_system.attack_plan
	return plan if plan.attacker == player else null


## Node-independent stack-pop primitive shared by right-click and Esc (#404,
## generalized #406). Right-click "ignores which node was clicked"
## (docs/design/click_grammar.md), and Esc has no node at all, so this never
## takes one. Pops the first armed level in _armed_modes — priority is array
## order, encoding nesting (a temp-upgrade arm sits on top of an attack plan
## and pops first). Returns true if something was armed to pop/exit.
func _pop_armed_mode() -> bool:
	for m in _armed_modes:
		if m.is_armed():
			return m.pop()
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


func _set_temp_upgrade_arm(upgrade: Variant) -> void:
	if _temp_upgrade_arm == upgrade:
		return
	_temp_upgrade_arm = upgrade
	temp_upgrade_arm_changed.emit(upgrade)
	_update_cursor()


## Arms `upgrade` (a MeleeAttackPlan.TEMP_UPGRADE_CATALOG entry) for
## placement, or clears the arm if it's already armed with the same one
## (tray button acts as a toggle on top of right-click/Esc pop).
func arm_temp_upgrade(upgrade: Variant) -> void:
	_set_temp_upgrade_arm(null if _temp_upgrade_arm == upgrade else upgrade)


func temp_upgrade_arm() -> Variant:
	return _temp_upgrade_arm


func _set_manage_arm(verb: ManageVerb) -> void:
	if _manage_arm == verb:
		return
	_manage_arm = verb
	manage_arm_changed.emit(verb)
	_update_cursor()


## Arms [param verb] for ManageBody's tray cards (#338), toggling off if it's
## already armed (re-click to cancel, same shape as arm_temp_upgrade). Arming
## any verb cancels an in-flight core-move targeting first — the two are
## mutually exclusive entry points into the graph, and Move Core re-enters its
## own targeting via [method enter_core_move_targeting] instead of a verb.
func arm_manage_verb(verb: ManageVerb) -> void:
	if verb != ManageVerb.NONE and _move_targeting_source != null:
		_set_move_targeting_source(null)
	_set_manage_arm(ManageVerb.NONE if _manage_arm == verb else verb)


func manage_arm() -> ManageVerb:
	return _manage_arm


func pending_mass_action() -> MassActionRequest:
	return _mass_action_request


## Arms a pending mass-allocate/deallocate confirmation (MassActionConfirmPanel
## presents on this signal). Cancels any in-flight core-move targeting first,
## same mutual-exclusion rule as arm_manage_verb.
func begin_mass_action(request: MassActionRequest) -> void:
	if _move_targeting_source != null:
		_set_move_targeting_source(null)
	_mass_action_request = request
	mass_action_pending_changed.emit(request)
	_update_cursor()


## Executes the pending request via AllocationSystem, then clears it. No-op if
## nothing is pending. Called by MassActionConfirmPanel's Confirm button, after
## it unpauses the tree.
func confirm_mass_action() -> void:
	var request := _mass_action_request
	if request == null:
		return
	match request.verb:
		MassActionRequest.Verb.ALLOCATE:
			allocation_system.mass_allocate(request.entity, request.nodes, request.affordable_count)
		MassActionRequest.Verb.DEALLOCATE:
			allocation_system.deallocate_set(request.nodes, request.entity)
	_clear_mass_action()


## Discards the pending request without executing it. Called by
## MassActionConfirmPanel's Cancel/Esc/right-click and by
## MassActionArmedMode.pop().
func cancel_mass_action() -> void:
	if _mass_action_request == null:
		return
	_clear_mass_action()


func _clear_mass_action() -> void:
	_mass_action_request = null
	mass_action_pending_changed.emit(null)
	_update_cursor()


## Move Core card's entry point (#338) — arms the same click-to-move /
## drag targeting `_route_core_move_click` already drives when the player
## clicks their own core directly; this is just another door into it.
## Re-pressing while already targeting cancels, mirroring the click-own-core
## toggle. Clears any armed Manage verb first (mutual exclusion, see
## arm_manage_verb).
func enter_core_move_targeting() -> void:
	if player == null or player.core_location == null:
		return
	if _manage_arm != ManageVerb.NONE:
		_set_manage_arm(ManageVerb.NONE)
	if _move_targeting_source == player.core_location:
		_set_move_targeting_source(null)
	else:
		_set_move_targeting_source(player.core_location)


func can_player_act() -> bool:
	if not _is_players_turn():
		return false
	# A swing is resolving (#406) — the plan stays live through the live-swing
	# await so its temp-upgrade addons keep rendering, but that's not an
	# invitation to click it mid-swing.
	if battle_system != null and battle_system.is_launching:
		return false
	# AP=0 blocks further attack/cast actions; UI uses this to dim.
	if player != null and player.stat_board != null:
		var ap: PoolStat = player.stat_board.action_points
		if ap != null and ap.available() <= 0:
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
