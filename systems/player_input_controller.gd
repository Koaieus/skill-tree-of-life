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
##                                             docs/domain/click-grammar.md)
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
## Every world mutation this controller asks for goes through here as a
## [Command] (#510) — never a direct `allocation_system.allocate(...)` call.
## Local plan-building (hover, pin, the armed-mode stack, the core-drag ghost,
## attack-mode selection) deliberately does NOT: it never crosses a wire.
@export var command_applier: CommandApplier
## The seat-local armed stack (#1222) — a sibling system in the level scene
## (`%ArmedStack`). Left unwired (a bare fixture), the controller makes a
## private one in `_ready`.
@export var armed_stack: ArmedStack

signal player_can_act_changed(can_act: bool)
## Core-move targeting state (#21). `source` is the player's core node while a
## click-source-then-target move is in flight, or null when no move is being
## composed. Future highlight overlay subscribes here to paint CORE_LANDING /
## CORE_PATH roles.
signal core_move_targeting_changed(source: SkillNode)
## The core-drag ghost's snapped landing moved (null when it snaps to nothing).
## [HighlightController] mirrors it into the active core-move provider so the
## brightened target ring tracks the ghost.
signal core_drag_target_changed(landing: SkillNode)

## A node was pinned (right-clicked when no attack plan was eating the click) or
## unpinned (null). [NodeInspectorCard] surfaces the pinned node's details.
signal node_pinned(node: SkillNode)

## Derived off the stack: fires when the [CoreMoveMode] source changes.
## Which temp upgrade is armed ([TempUpgradeMode] on the branch), or null (#406).
## Derived off the stack; fires once per transition.
signal temp_upgrade_arm_changed(upgrade: TempUpgradeDef)
var _last_temp_upgrade: TempUpgradeDef = null
var _last_move_source: SkillNode = null

## The last melee blade each entity successfully launched (#466), keyed by
## `Object.get_instance_id()` — never `Entity.entity_id`, which is 0 until the
## entity enters `entities_container`, and never the Entity itself, since a
## freed Object compares equal to `null` (see the gdscript-pitfalls rule).
##
## The value is the plan's own wire form, [method MeleeAttackPlan.to_dict], so
## there is no second representation of a blade to keep in step; only the
## stable ids and `swing_cw` are ever read back out.
##
## [b]Client-local input state that never syncs.[/b] Reform is not a command:
## it expands into an ordinary [MeleeAttackPlan] which then launches through
## the normal path, so it adds no wire surface at all
## (docs/domain/multiplayer-sync-model.md). It is keyed per entity rather than
## held as one slot so a hot-seat handover (#459) cannot let the incoming
## player reform the outgoing one's blade, and it deliberately survives
## [method clear_transient_state] — the slot is not half-finished intent, it is
## the memory of a completed action, and it lasts the whole run.
var _reform_slots: Dictionary[int, Dictionary] = {}

## Manage-tab verb ids (#338) — the tray's card ids and the highlight's verb
## key. NOT arm state: that is the [ArmedStack] branch, where Deallocate,
## Stake and Extract are [ManageVerbMode] levels on the [ManageMode] root.
enum ManageVerb { NONE, ALLOCATE, DEALLOCATE, STAKE, EXTRACT }
## Compat for [HighlightController], which still reads the verb: derived off
## the stack, fires once per transition. New readers use [member armed_stack].
signal manage_arm_changed(verb: ManageVerb)
var _last_manage_verb: ManageVerb = ManageVerb.NONE

## A distant-allocate-path or would-island-deallocate click is pending
## confirmation ([MassActionMode] on the branch). Derived off the stack; fires
## once per transition.
signal mass_action_pending_changed(request: MassActionRequest)
var _last_mass_request: MassActionRequest = null

## Gate management (#1206). The bulk verbs a toggle expands into; locks are a
## seat-local input filter held by [GateLockSet], never world state.
enum GateAction { TOGGLE_UNLOCKED, OPEN_UNLOCKED, CLOSE_UNLOCKED, UNLOCK_ALL, LOCK_ALL }
## A gate flip that would strand owned nodes is armed (non-empty) or disarmed
## (empty). The same request again submits it.
signal gate_confirm_changed(stranded: Array[SkillNode])
## The current player's lock set changed (or the player did).
signal gate_locks_changed
## Survives [method clear_transient_state] like `_reform_slots`: a lock is a
## standing preference, not half-finished intent.
var _gate_locks := GateLockSet.new()
var _gate_pending_key: Array[Vector2i] = []
var _gate_pending_strand: Array[SkillNode] = []


## Colour for the viewport armed-mode glow (#412), carried so the overlay is a
## pure consumer with no knowledge of the stack. Fires on every *tint*
## transition — deliberately not on every arm/disarm, because most armed levels
## contribute no tint at all (see [method ArmedMode.tint]); arming a Manage verb
## is a real mode change that correctly produces no signal here.
signal armed_tint_changed(tint: Color)
## Last tint emitted, so a level that re-sets the same value doesn't re-fire.
var _armed_tint: Color = Color.TRANSPARENT

## Badge for the cursor-following armed-mode icon (#664), carried so
## [ArmedModeIcon] is a pure consumer with no knowledge of the stack — the same
## deal [signal armed_tint_changed] gives [ArmedModeGlow].
##
## **Deduped INDEPENDENTLY of the tint, and that independence is the whole
## point.** The two channels walk the stack from opposite ends, so they change
## at different moments: arming a clamp on top of an armed melee plan moves the
## badge and leaves the border red. Folding this emit in under the tint's
## early-return would swallow exactly that case — the headline scenario of
## #664 — so each channel compares against its own cached value below.
signal armed_icon_changed(icon: Texture2D, tint: Color)
## Last badge emitted, so a refresh that changed nothing doesn't re-fire.
var _armed_icon: Texture2D = null
var _armed_icon_tint: Color = Color.TRANSPARENT

## Node currently under the cursor, tracked via the Events hover bus so the
## `D`-to-deallocate channel knows what to act on. Null when nothing hovered.
var _hovered_node: SkillNode = null

## True while a full-screen modal (LootPicker/SpellLootPicker, #486) is up.
## Replaces the old `get_tree().paused` block: freezes every player input
## channel (click, D-key, right-click/Esc pop) without pausing the SceneTree,
## which would also stall confirmed-command RPC dispatch under the LAN sync
## model (docs/domain/multiplayer-sync-model.md). Set only via
## [method set_input_frozen].
var _input_frozen: bool = false

## Node pinned to the context panel via right-click (when no attack plan claims
## the click). Null when nothing is pinned.
var _pinned_node: SkillNode = null

const _CORE_DRAG_GHOST_SCENE := preload("res://skill_node/visuals/core_drag_ghost.tscn")

## Core-move drag state (#21, #128). `_core_drag_started` flips once the
## cursor leaves the core past CORE_DRAG_THRESHOLD; `_core_drag_landing` is the
## currently snapped landing (committed on release). The [CoreDragGhost]
## (presence + badge) is lazily built on the first drag step.
var _core_drag_started := false
var _core_drag_landing: SkillNode = null
var _core_drag_ghost: CoreDragGhost = null


## [b]Only the OS-input carriers are editor-gated, never the wiring.[/b] An
## editor-hosted sandbox (the melee tab) instantiates this non-`@tool` script
## from tool code, so `_ready` runs there with `is_editor_hint()` TRUE — and a
## blanket early return left the controller half-built: every `attack_launched`,
## `applying_changed` and armed-mode subscription below silently absent, which
## is how the #466 reform slot could never be captured in the melee sandbox
## while every headless test stayed green (GUT has no editor hint to see).
## Anything that reaches for the OS instead — a [SkillNode]'s own Area2D pick
## (the sandbox hand-routes those itself), `_unhandled_input`, the mouse cursor
## — stays gated, at its own site.
func _ready() -> void:
	if armed_stack == null:
		armed_stack = ArmedStack.new()
		armed_stack.name = "ArmedStack"
		add_child(armed_stack)
	armed_stack.set_root(ManageMode.new(self))
	armed_stack.changed.connect(_on_armed_stack_changed)
	# `player` may be wired post-_ready (procgen sandboxes spawn it during
	# GameRoot._setup_level). Skip the player-dependent gate, not the graph
	# subscription — clicks still connect; routing checks player at fire time.
	if graph == null or allocation_system == null or turn_manager == null:
		push_warning("PlayerInputController missing graph/allocation/turn_manager; clicks won't route")
		return
	# Physics picking through an editor-hosted SubViewport is unreliable, so the
	# melee tab hit-tests by hand and calls [method route_left_click]. Wiring
	# the node's own signal there too would double-route whichever pick lands.
	if not Engine.is_editor_hint():
		graph.node_added.connect(_on_node_added)
		for sn in graph.get_skill_nodes():
			_on_node_added(sn)

	turn_manager.turn_started.connect(_emit_gate_changed.unbind(1))
	turn_manager.turn_ended.connect(_emit_gate_changed.unbind(1))
	turn_manager.turn_ended.connect(_disarm_gate_confirm.unbind(1))
	if not Engine.is_editor_hint() and graph.gates_container != null:
		graph.gates_container.child_entered_tree.connect(_on_gate_added)
		for g in graph.get_gates():
			_on_gate_added(g)

	Events.skill_node_hovered.connect(_on_skill_node_hovered)
	Events.skill_node_unhovered.connect(_on_skill_node_unhovered)
	Events.node_action_denied.connect(_on_node_action_denied)

	if battle_system != null:
		battle_system.attack_plan_changed.connect(_refresh_armed_state.unbind(1))
		# ...and plan *state*, not just plan lifecycle (#683). The melee badge
		# now reads the pivot, which moves inside a plan that never changes
		# identity — `attack_plan_changed` would never fire for it. This is the
		# higher-frequency of the two (every blade toggle, every temp upgrade),
		# and it costs nothing: `_refresh_armed_state` emits only on a resolved
		# icon/tint that actually differs, and `_update_cursor` above the dedup
		# is an idempotent `Input.set_default_cursor_shape`.
		battle_system.attack_plan_state_changed.connect(_refresh_armed_state)
		# can_player_act() now also reads battle_system.is_launching (#406),
		# whose transitions have no signal of their own. attack_plan_changed
		# fires when a swing's post-await _reset() clears the plan — the only
		# observable moment is_launching flips back false — so AttackModeBar
		# (gated purely off player_can_act_changed, command_tray.gd) doesn't
		# stay disabled forever after the first swing of a turn.
		battle_system.attack_plan_changed.connect(_emit_gate_changed.unbind(1))
		battle_system.attack_launched.connect(_on_attack_launched)
	if command_applier != null:
		# Outcomes arrive here instead of as a `bool` return (#510). The four
		# sites that used to branch on success inline — deallocate's cascade
		# offer, stake/extract denial feedback — are now handlers.
		command_applier.command_applied.connect(_on_command_applied)
		# can_player_act() reads is_applying, whose transitions are otherwise
		# unobservable — same reason attack_plan_changed feeds this gate.
		command_applier.applying_changed.connect(_emit_gate_changed.unbind(1))
		# The third gate (#541) rides the SAME refresh route rather than growing
		# a second one — one `_emit_gate_changed`, four things that can move it.
		command_applier.awaiting_confirmation_changed.connect(_emit_gate_changed.unbind(1))
		# The fourth gate (#646): a relic's claim chain now runs OUTSIDE the
		# queue between rounds, so `is_applying` no longer covers "a pick is
		# outstanding" — see [CommandApplier.has_outstanding_loot].
		command_applier.outstanding_loot_changed.connect(_emit_gate_changed.unbind(1))


func _on_node_added(skill_node: SkillNode) -> void:
	if not skill_node.left_clicked.is_connected(_on_skill_node_left_clicked):
		skill_node.left_clicked.connect(_on_skill_node_left_clicked)


## Route a left-click that did NOT arrive through a [SkillNode]'s own Area2D
## pick. Same channels, same order — this is an alternate *carrier*, never an
## alternate routing.
##
## Exists for the melee sandbox tab, which hit-tests its [SubViewport] by hand:
## physics picking through an editor-hosted SubViewport is unreliable (the spell
## playground found the same and does the same). Same precedent as
## [method request_temp_upgrade_at] being public for the tray blips — a surface
## that has its own way of naming a node still goes through the real channel.
func route_left_click(skill_node: SkillNode) -> void:
	_on_skill_node_left_clicked(skill_node)


func _on_skill_node_left_clicked(skill_node: SkillNode) -> void:
	if _input_frozen or armed_stack == null:
		return
	# The one flow gate for every level's click.
	if not can_player_act():
		return
	# Top-first; the first level to consume the click wins. A level that popped
	# itself mid-walk is skipped.
	var levels := armed_stack.branch()
	for i in range(levels.size() - 1, -1, -1):
		var level := levels[i]
		if armed_stack.has(level) and level.handle_left_click(skill_node):
			return


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
	var request := MassActionRequest.new(player, MassActionRequest.Verb.ALLOCATE, path)
	# Display only. The applier recomputes this at apply time from the same
	# helper — the count never travels on the command (#458).
	request.affordable_count = allocation_system.affordable_allocation_count(player, path)
	request.target = target
	begin_mass_action(request)


func _skill_points_available() -> int:
	if player == null or player.stat_board == null:
		return 0
	var sp: PoolStat = player.stat_board.skill_points
	return sp.available() if sp != null else 0


## Shared deallocate verb call (#338) — both the `D`-hover accelerator and an
## armed-Deallocate click resolve through this. Unlike the `D` channel (which
## pre-gates on `owned_by == player` and stays silent otherwise, see
## _unhandled_input), this always fires denial feedback on failure — an
## explicit click on an illegal node while armed is a deliberate attempt, not
## an idle hover.
##
## No return since #510: the verb is a [DeallocateCommand] now, and its failure
## branch (the cascade offer) lives in [method _on_command_applied]. Nothing
## ever read the old `bool` — both callers consumed the click unconditionally.
func _resolve_deallocate(node: SkillNode) -> void:
	_submit(DeallocateCommand.new(player.entity_id, graph.get_stable_id(node)))


func _resolve_stake(node: SkillNode) -> void:
	_submit(StakeCommand.new(player.entity_id, graph.get_stable_id(node)))


func _resolve_extract(node: SkillNode) -> void:
	_submit(ExtractCommand.new(player.entity_id, graph.get_stable_id(node)))


## Hand the turn back, as an [EndTurnCommand] rather than a direct
## [method TurnManager.end_turn] — the clock is a mutation like any other, and
## [AiController] has ended its turns this way since #512.
##
## Lives here rather than on the HUD's ActionCluster because the command needs
## BOTH the applier (a `bind_systems()`-lifetime dep) and the acting player (a
## `rebind_player()`-lifetime one, see #459). This controller already holds and
## rebinds both; giving a HUD cluster its own player reference is how hot-seat
## handover breaks.
##
## No turn-holder gate: the applier does not check one, and neither did the
## direct call this replaces. The button's own enabled state is the gate.
func request_end_turn() -> void:
	if player == null:
		return
	_submit(EndTurnCommand.new(player.entity_id))


## Submit a [ReloadCommand] for the acting player (#957). Only while the
## ranged plan is armed, and only when the player can act and can pay. Returns
## whether a command was submitted. The `ui_reload` key reaches this through
## [method reload_in_hand]; the ranged tray's button calls it directly.
func request_reload() -> bool:
	if player == null or battle_system == null:
		return false
	if not (battle_system.attack_plan is RangedAttackPlan):
		return false
	if not can_player_act() or not player.can_reload():
		return false
	_submit(ReloadCommand.new(player.entity_id))
	return true


## Where the four `if`-gated mutation sites went (#510). A command that failed
## its gate is a normal outcome, so this is the only place player-facing
## feedback for a refusal is decided.
##
## Runs INSIDE the applier's [member CommandApplier.is_applying] guard, which is
## the point: the deallocate branch below submits a follow-up mass action, and
## that submission must queue rather than re-enter.
##
## Only reacts to this player's own commands — under
## `docs/domain/multiplayer-sync-model.md` every peer's confirmed commands drain
## through the same applier, and another player's refusal is not this player's
## denial shake.
func _on_command_applied(command: Command, success: bool) -> void:
	if player == null or command.entity_id != player.entity_id:
		return
	# Pop policy is the levels' (Stake pops itself on success); the feedback
	# below stays here, so a denial that lands after its level popped still shakes.
	if armed_stack != null:
		var levels := armed_stack.branch()
		for i in range(levels.size() - 1, -1, -1):
			if armed_stack.has(levels[i]):
				levels[i].on_command_resolved(command, success)
	if success:
		return
	var node := graph.get_by_stable_id(command.node_id) \
			if command is NodeCommand and graph != null else null
	if node == null:
		return
	if command is DeallocateCommand:
		# would_disconnect_from rejected a plain deallocate — if that's the only
		# reason (the node is genuinely player's, non-core), offer the full
		# cascade via the confirm panel instead of a flat reject, regardless of
		# whether the player can currently afford it (Confirm just stays disabled
		# in that case — see docs/domain mass-action confirm panel).
		var cascade := allocation_system.deallocation_cascade(node, player)
		if cascade.size() > 1:
			begin_mass_action(
					MassActionRequest.new(player, MassActionRequest.Verb.DEALLOCATE, cascade))
			return
		Events.node_action_denied.emit(node, "deallocate_denied")
	elif command is StakeCommand:
		Events.node_action_denied.emit(node,
				_gate_denial(allocation_system.stake_denial(node, player), &"stake_denied"))
	elif command is ExtractCommand:
		Events.node_action_denied.emit(node,
				_gate_denial(allocation_system.extract_denial(node, player), &"extract_denied"))


## The one door out of this controller into the world. Drops the command with a
## warning rather than silently swallowing it when no applier is wired — a
## fixture that mutates without one is a fixture bug, not a no-op.
func _submit(command: Command) -> void:
	if command_applier == null:
		push_warning("PlayerInputController: no CommandApplier wired; dropping '%s'" \
				% command.type_tag())
		return
	command_applier.submit(command)


## The gate's reason, or [param generic] when the gate now passes — the
## command was refused on something the gate does not see (it was re-read
## after the fact).
static func _gate_denial(reason: StringName, generic: StringName) -> String:
	return String(generic if reason == &"" else reason)


## Requests an armed temp-upgrade placement (#406) — click-to-toggle, same
## shape as blade-member selection: clicking a node that already carries
## this exact temp upgrade refunds it, clicking any other eligible node
## applies a new one. Stays armed either way — the toggle's own gating already
## makes a failed attempt fail gracefully with denial feedback, so there's
## no correctness reason to force a re-click of the tray button per action.
## Public so the melee command tray's blade blips (#406 follow-up) can drive
## the exact same gating/denial path when a red blip is clicked, instead of
## routing a synthetic graph click.
##
## A temp upgrade is plan content (ADR 0035): the toggle is a seat-local edit
## of the armed [MeleeAttackPlan], no command — the host judges its cost once,
## at launch. A refusal is announced here on [signal Events.node_action_denied]
## with the plan's reason. The returned bool is "this click was consumed",
## never "the upgrade landed"; every caller only uses it for routing.
func request_temp_upgrade_at(skill_node: SkillNode) -> bool:
	var arm := temp_upgrade_arm()
	if arm == null or not can_player_act():
		return false
	var plan := _active_attack_plan() as MeleeAttackPlan
	if plan == null:
		return false
	if skill_node != null and not plan.toggle_temp_upgrade(skill_node, arm):
		Events.node_action_denied.emit(skill_node,
				plan.temp_upgrade_denial_reason(skill_node, arm))
	return true


# ── Reform last blade (#466) ───────────────────────────────────────────────

## Capture the blade that just launched. [signal BattleSystem.attack_launched]
## fires inside `_commit`, i.e. only AFTER `_compute_record` cleared the
## affordability gates and while the plan is still live — so a refused launch
## can never overwrite a good slot, which is the whole reason the capture does
## not sit on the button press.
##
## Guarded on the attacker being THIS controller's player, which is also what
## keeps AI entities out of the map: they build plans directly and have nothing
## to reform.
func _on_attack_launched(mode: BattleSystem.AttackMode, _spell: SpellDef) -> void:
	if mode != BattleSystem.AttackMode.MELEE or graph == null or player == null:
		return
	var plan := battle_system.attack_plan as MeleeAttackPlan
	if plan == null or plan.source == null or plan.attacker != player:
		return
	_reform_slots[player.get_instance_id()] = plan.to_dict(graph)


## The stored blade for the current player, resolved from stable ids back to
## live nodes: `pivot`, `members`, `swing_cw`. Empty when there is no slot, or
## when any stored node is gone from the board — a member that no longer exists
## is a refusal, never a smaller blade.
func _reform_payload() -> Dictionary:
	if player == null or graph == null:
		return {}
	var stored: Dictionary = _reform_slots.get(player.get_instance_id(), {})
	if stored.is_empty():
		return {}
	var pivot := graph.get_by_stable_id(int(stored.get("source", 0)))
	if pivot == null:
		return {}
	var members: Array[SkillNode] = []
	for id in stored.get("blade", [] as Array):
		var member := graph.get_by_stable_id(int(id))
		if member == null:
			return {}
		members.append(member)
	return {
		pivot = pivot,
		members = members,
		swing_cw = bool(stored.get("swing_cw", false)),
	}


## Whether [method reform_blade] would succeed right now. The melee body reads
## this to enable its button; a false answer is why the affordance greys out
## instead of half-reforming.
##
## Reform re-arms a melee plan, so it asks the melee price through
## `can_afford` on the live plan — `BattleSystem._can_afford` gates it again
## at launch.
func can_reform() -> bool:
	if battle_system == null or not can_player_act():
		return false
	if battle_system.attack_plan != null and not can_afford(battle_system.attack_plan):
		return false
	var payload := _reform_payload()
	if payload.is_empty():
		return false
	var pivot: SkillNode = payload.pivot
	var members: Array[SkillNode] = payload.members
	return MeleeAttackPlan.can_reform_selection(player, pivot, members)


## The `ui_reload` action: re-arm whatever weapon is in hand. The ARMED LEVEL
## owns the verb — [method ArmedMode.reload] — so a ranged plan refills its
## quiver and a melee plan re-forms its blade, and the two handlers are never
## live at once. With nothing armed it is #466's global accelerator: re-form
## the last blade, which arms melee itself. Returns whether the key was
## consumed; false leaves it free for anything downstream.
func reload_in_hand() -> bool:
	if armed_stack != null:
		var levels := armed_stack.branch()
		for i in range(levels.size() - 1, -1, -1):
			if levels[i].reload():
				return true
	return reform_blade()


## Rebuild the player's last launched blade — pivot, members and swing
## direction — leaving the launch itself to them, so the shape can still be
## tweaked (or a temp upgrade added) before it commits.
##
## Arms melee first when another mode (or none) is active: the keybind is a
## global accelerator, and `request_attack_mode` early-returns when melee is
## already up, so an in-progress selection is replaced rather than re-armed.
func reform_blade() -> bool:
	if not can_reform():
		return false
	arm_attack(BattleSystem.AttackMode.MELEE)
	var plan := battle_system.attack_plan as MeleeAttackPlan
	if plan == null:
		return false
	var payload := _reform_payload()
	var pivot: SkillNode = payload.pivot
	var members: Array[SkillNode] = payload.members
	if not plan.try_reform(pivot, members):
		return false
	# The reform set the pivot outside input: the Melee level follows it here.
	var melee := armed_stack.find(MeleeMode) as MeleeMode
	if melee != null:
		melee.open_blade()
	# The swing direction is BattleSystem's sticky preference, and that is what
	# the tray's toggle label reads — setting only `plan.swing_cw` would restore
	# the swing while the button kept advertising the old direction.
	var cw: bool = payload.swing_cw
	battle_system.next_melee_cw = cw
	plan.swing_cw = cw
	return true


func _set_pinned(node: SkillNode) -> void:
	if _pinned_node == node:
		return
	_pinned_node = node
	node_pinned.emit(node)


func _on_skill_node_hovered(skill_node: SkillNode) -> void:
	_hovered_node = skill_node
	_push_magic_hover(skill_node)


func _on_skill_node_unhovered() -> void:
	_hovered_node = null
	_push_magic_hover(null)


## Feeds the hover into the active magic plan's aim-time propagation preview
## (#679) -- a no-op for every other mode/plan, and for a plan that isn't the
## player's own (mirrors [method _active_attack_plan]'s ownership gate, so a
## hot-seat peer's hover never drives the LOCAL player's preview).
func _push_magic_hover(skill_node: SkillNode) -> void:
	var plan := _active_attack_plan() as MagicAttackPlan
	if plan != null:
		plan.set_hover_target(skill_node)


## Channels live here:
##  - Core-move DRAG (#21): once targeting is active (the player pressed their
##    own core), dragging the held mouse snaps a ghost core to the nearest
##    reachable landing and a hop badge floats by the cursor; release commits.
##    Click-to-move still works untouched — drag is the layered accelerator.
##  - RIGHT-CLICK: pops one level off whichever mode is armed (attack plan or
##    core-move — docs/domain/click-grammar.md), node-independent like Esc
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
	if _input_frozen:
		return
	if event is InputEventMouseMotion:
		if move_targeting_source() != null and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_update_core_drag()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_on_core_drag_released()
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if pop_armed_level():
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
	if has_armed_level():
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
	if _input_frozen:
		return
	if event.is_action_pressed(&"ui_cancel") and pop_armed_level():
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_reload") and reload_in_hand():
		get_viewport().set_input_as_handled()
		return
	# Shift+G before G: plain G's action would also match Shift+G unless exact.
	if event.is_action_pressed(&"ui_gate_locks") and player != null:
		request_gate_locks_hotkey()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_toggle_gates", false, true) and _is_players_turn():
		request_gate_action(GateAction.TOGGLE_UNLOCKED)
		get_viewport().set_input_as_handled()
		return
	# Z / X arm the temp-upgrade cards by CATALOG INDEX, never by name (#718).
	# `BattleSystem.temp_upgrade_kinds()` is data — the filed "edge sharpener"
	# should light up on the next key with zero changes here — so the binding is
	# a positional walk and an out-of-range index is a silent no-op rather than
	# a crash on a catalog that shrank.
	for i in TEMP_UPGRADE_HOTKEYS.size():
		if event.is_action_pressed(TEMP_UPGRADE_HOTKEYS[i]) and _arm_temp_upgrade_at(i):
			get_viewport().set_input_as_handled()
			return
	# 1..9 (top row OR keypad, owner call 2026-09-04) pick the Nth spell in the
	# book. Same positional shape as Z/X above: an index past the book is a
	# silent unconsumed no-op, so a digit stays free for whatever wants it next.
	for i in SPELL_HOTKEYS.size():
		if event.is_action_pressed(SPELL_HOTKEYS[i]) and _select_spell_at(i):
			get_viewport().set_input_as_handled()
			return


## The arming actions, in catalog order. `TempUpgradeButton` prints the key
## bound to the SAME action on its card ([method temp_upgrade_keycap], passed
## in by `MeleeBody`) — so the label and the binding can never drift, and
## adding a third addon means adding one entry here plus its InputMap action.
const TEMP_UPGRADE_HOTKEYS: Array[StringName] = [
	&"ui_temp_upgrade_1", &"ui_temp_upgrade_2", &"ui_temp_upgrade_3",
]


## Spell-picking hotkeys, in SPELLBOOK ORDER (#718 follow-up). Owner call
## (2026-09-04): *"spells best be indexed by number key! (regular row OR
## keypad)"* — each action carries BOTH events, so the two rows are one
## binding rather than two parallel ones that could drift.
##
## Magic-tab-only, exactly as Z/X are melee-only: a stray digit must not be
## able to yank you out of the tab you are in, and the number row stays
## claimable by another mode later.
##
## Nine, because there are nine non-zero digits. A tenth spell is mouse-only
## and [method spell_keycap] returns "" for it, which paints NO chip — an
## absence rather than a wrong glyph.
const SPELL_HOTKEYS: Array[StringName] = [
	&"ui_select_spell_1", &"ui_select_spell_2", &"ui_select_spell_3",
	&"ui_select_spell_4", &"ui_select_spell_5", &"ui_select_spell_6",
	&"ui_select_spell_7", &"ui_select_spell_8", &"ui_select_spell_9",
]


## The keycap [SpellPickerBar] prints on the tile at book position [param index],
## or "" when the book has outgrown the bound digits. DERIVED from the index —
## never authored per tile — because the book is loot-driven and reorders.
static func spell_keycap(index: int) -> String:
	if index < 0 or index >= SPELL_HOTKEYS.size():
		return ""
	return str(index + 1)


## The keycap `MeleeBody` prints on catalog entry [param index]'s card, or ""
## when the catalog has outgrown the bound keys (an unbound card just shows no
## keycap rather than a wrong one). DERIVED from the InputMap through
## [method KeyChip.keycap_for], never a hand-typed parallel list — rebind the
## action in `project.godot` and the card follows.
static func temp_upgrade_keycap(index: int) -> String:
	if index < 0 or index >= TEMP_UPGRADE_HOTKEYS.size():
		return ""
	return KeyChip.keycap_for(TEMP_UPGRADE_HOTKEYS[index])


## Arms catalog entry [param index], but only while MELEE is the active attack
## mode — the cards these mirror only exist in the melee tray, so the keys are
## modal exactly like the tray is. Returns whether the key was consumed, so an
## unbound index leaves the key free for anything downstream.
##
## Re-press cancels, because it goes through the same [method arm_temp_upgrade]
## toggle the card click already uses — one door, not a parallel one.
func _arm_temp_upgrade_at(index: int) -> bool:
	if battle_system == null or battle_system.attack_mode != BattleSystem.AttackMode.MELEE:
		return false
	if not can_player_act():
		return false
	var kinds := battle_system.temp_upgrade_kinds()
	if index < 0 or index >= kinds.size():
		return false
	arm_temp_upgrade(kinds[index])
	return true


## Selects book position [param index] as the active spell, but only while
## MAGIC is the live attack mode — the picker these mirror only exists in the
## magic tray, so the digits are modal exactly like the tray is.
##
## Writes [member BattleSystem.selected_spell], the SAME terminal
## [SpellPickerBar] `spell_selected` reaches through [MagicBody] — so the
## picker's highlight (driven by `selected_spell_changed`) and the plan cannot
## disagree about what is armed.
##
## Returns whether the key was consumed: an empty book, a digit past its size,
## or the wrong mode all leave the key unconsumed and free downstream.
func _select_spell_at(index: int) -> bool:
	if battle_system == null or battle_system.attack_mode != BattleSystem.AttackMode.MAGIC:
		return false
	if not can_player_act():
		return false
	if player == null or player.spellbook == null:
		return false
	var spell := spell_at_slot(player.spellbook, index)
	if spell == null:
		return false
	battle_system.selected_spell = spell
	return true


## The spell the Nth TILE stands for. Counts only non-null entries, exactly as
## [method SpellPickerBar._rebuild] does when it builds the tiles — a null hole
## in the book must not silently shift the digits away from the glyphs painted
## on screen. Returns null for any slot the book does not fill.
static func spell_at_slot(book: SpellBook, index: int) -> SpellDef:
	if book == null or index < 0:
		return null
	var slot := 0
	for spell in book.spells:
		if spell == null:
			continue
		if slot == index:
			return spell
		slot += 1
	return null


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
## Whether any level sits above the [ManageMode] root.
func has_armed_level() -> bool:
	return armed_stack != null and armed_stack.branch().size() > 1


func _active_attack_plan() -> AttackPlan:
	if battle_system == null or battle_system.attack_plan == null:
		return null
	var plan := battle_system.attack_plan
	return plan if plan.attacker == player else null


## Node-independent pop shared by right-click and Esc (#404): right-click
## "ignores which node was clicked" (docs/design/click_grammar.md) and Esc has
## no node at all. The top level first retreats inside itself
## ([method ArmedMode.pop_within]); otherwise it pops. False at the root, so
## the caller falls through to pin-toggle / the pause menu. Mid-swing the
## stack is frozen: the attack level outlives the launch until the slot
## releases it, so a pop is refused (false) rather than stripping the badge
## and glow off a sword that is still flying.
func pop_armed_level() -> bool:
	if armed_stack == null:
		return false
	if battle_system != null and battle_system.is_launching:
		return false
	var top := armed_stack.top()
	if top != null and top.pop_within():
		return true
	return armed_stack.pop_top()


## Swaps the OS cursor while any targeting mode is armed (#404) — a plain
## shape swap, cleared on resolve/cancel. The viewport-wide glow (#412) is the
## other consumer of the same state; both hang off
## [method _refresh_armed_state].
func _update_cursor() -> void:
	# The cursor is the OS's, and an editor-hosted sandbox shares it with the
	# whole editor — a tab that keeps a plan armed would leave every dock on a
	# crosshair. Same reason the input carriers are gated, one level down.
	if Engine.is_editor_hint():
		return
	Input.set_default_cursor_shape(
			Input.CURSOR_CROSS if has_armed_level() else Input.CURSOR_ARROW)


## The colour the viewport armed-mode glow should paint (#412), or a
## transparent colour when nothing armed contributes one.
##
## Walks [method ArmedStack.branch] **base-first** — the BASE of the stack
## decides, the opposite end from [method pop_armed_level]'s. **Owner call 2026-08-21:**
## "in any stacked mode e.g. 'Melee -> Blade select mode -> place Spike Addon
## mode [armed]' -> still just red outline (Melee) … so i think the root of the
## stack (1st el?) may be decisive here". The [ManageMode] root has no tint, so
## the first level above it with a colour decides.
##
## An armed level with no colour falls through instead of blanking the glow, so
## it can never mask a tinted level beneath it.
##
## Pure: no side effects, no frame state. That is deliberate — glow can't be
## judged headless (`docs/domain/godot-workflow.md`), so the resolution has to
## live somewhere a GUT test can call directly.
func get_armed_tint() -> Color:
	if armed_stack == null:
		return Color.TRANSPARENT
	for mode in armed_stack.branch():
		var color := mode.tint()
		if color.a > 0.0:
			return color
	return Color.TRANSPARENT


func _armed_icon_level() -> ArmedMode:
	if armed_stack == null:
		return null
	var levels := armed_stack.branch()
	for i in range(levels.size() - 1, -1, -1):
		if levels[i].icon() != null:
			return levels[i]
	return null


## The badge texture for the armed-mode cursor icon (#664), or null when
## nothing armed contributes one.
##
## Pure: no side effects, no frame state — same reason [method get_armed_tint]
## is. A cursor badge cannot be judged headless
## (`docs/domain/godot-workflow.md`), so the resolution has to live somewhere a
## GUT test can call directly.
func get_armed_icon() -> Texture2D:
	var level := _armed_icon_level()
	return level.icon() if level != null else null


## The colour [method get_armed_icon]'s badge is modulated with, read off the
## SAME level the texture came from — never a second independent walk. Returned
## UNLIFTED; [ArmedModeIcon] owns the emissive tier.
func get_armed_icon_tint() -> Color:
	var level := _armed_icon_level()
	return level.icon_tint() if level != null else Color.TRANSPARENT


## Single fan-in for "the armed stack may have changed": re-reads it once and
## pushes both consumers (cursor shape, viewport glow). Called on every stack
## change and on plan-state changes, which move a badge inside one level.
func _refresh_armed_state() -> void:
	_update_cursor()

	# Two channels, two caches, two independent emits — NOT one early return
	# guarding both. The tint walks the stack base-first and the icon walks it
	# top-first, so they genuinely change at different moments; a shared
	# early-return on the tint would swallow every badge change that leaves the
	# border colour alone, which is precisely the melee+clamp case #664 exists
	# for. See [signal armed_icon_changed].
	var next_tint := get_armed_tint()
	if next_tint != _armed_tint:
		_armed_tint = next_tint
		armed_tint_changed.emit(next_tint)

	# Resolved as a pair, from one walk: `get_armed_icon_tint` reads the tint
	# off the same level the icon came from, so the badge can never show one
	# mode's glyph in another mode's colour.
	var next_icon := get_armed_icon()
	var next_icon_tint := get_armed_icon_tint()
	if next_icon != _armed_icon or next_icon_tint != _armed_icon_tint:
		_armed_icon = next_icon
		_armed_icon_tint = next_icon_tint
		armed_icon_changed.emit(next_icon, next_icon_tint)


func move_targeting_source() -> SkillNode:
	var level := armed_stack.find(CoreMoveMode) as CoreMoveMode if armed_stack != null else null
	return level.source if level != null else null


func _pop_core_move() -> void:
	var level := armed_stack.find(CoreMoveMode) if armed_stack != null else null
	if level != null:
		armed_stack.pop(level)


## Commit a core move to [param target] along the shortest owned-edge path.
## Adjacent target → a one-hop walk; reachable-but-distant target → the whole
## BFS path (`AllocationSystem.core_path`). Non-reachable / over-budget targets
## give an empty path and no-op.
##
## ONE [MoveCoreCommand] carrying the full path (#510), not one per hop — the
## per-hop loop, the beat between hops and the stop-on-first-failure rule all
## moved into [method CommandApplier._apply_move_core] unchanged. Splitting it
## into N commands would put N wire messages where the player took one action.
func _commit_core_move(target: SkillNode) -> void:
	var path := allocation_system.core_path(player, target)
	if path.size() < 2:
		return
	# path[0] is the core's current node — the hops are path[1..].
	var hop_ids: Array[int] = []
	for i in range(1, path.size()):
		hop_ids.append(graph.get_stable_id(path[i]))
	_submit(MoveCoreCommand.new(player.entity_id, hop_ids))


## Mouse moved with the button held while core-move targeting is active: snap a
## ghost core to the nearest reachable landing under the cursor (within
## CORE_DRAG_SNAP_RADIUS) and float a hop badge. Pushes the snapped landing into
## the active highlight provider so the on-route preview brightens live.
func _update_core_drag() -> void:
	var src := move_targeting_source()
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
	if landing != null:
		var hops := maxi(0, allocation_system.core_path(player, landing).size() - 1)
		var mp := _movement_points_current()
		_core_drag_ghost.place(landing.global_position, true)
		_core_drag_ghost.set_badge("%d hop%s · %d MP left" \
				% [hops, "" if hops == 1 else "s", maxi(0, mp - hops)], world)
	else:
		_core_drag_ghost.place(world, false)
		_core_drag_ghost.set_badge("—", world)
	_set_drag_preview_target(landing)


## Release while dragging commits to the snapped landing (multi-hop along the
## owned path) and ends targeting. A release without a real drag is left alone so
## click-to-move keeps working (next click is the landing).
func _on_core_drag_released() -> void:
	if not _core_drag_started:
		return
	var landing := _core_drag_landing
	_clear_core_drag()
	if landing != null and move_targeting_source() != null:
		_commit_core_move(landing)
	_pop_core_move()


func _nearest_reachable_landing(world: Vector2) -> SkillNode:
	var src := move_targeting_source()
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


## Announce the drag's snapped landing; [HighlightController] owns what the
## highlights do with it.
func _set_drag_preview_target(landing: SkillNode) -> void:
	core_drag_target_changed.emit(landing)


## Builds the [CoreDragGhost] lazily, dressed as the player's core at the
## dragged node's radius.
func _ensure_core_drag_visuals() -> void:
	if _core_drag_ghost != null:
		return
	_core_drag_ghost = _CORE_DRAG_GHOST_SCENE.instantiate()
	graph.add_child(_core_drag_ghost)
	var src := move_targeting_source()
	var r := src.radius if src != null else 32.0
	_core_drag_ghost.configure(player, r)


func _clear_core_drag() -> void:
	_core_drag_started = false
	_core_drag_landing = null
	if _core_drag_ghost != null:
		_core_drag_ghost.queue_free()
		_core_drag_ghost = null


func _player_has_movement_points() -> bool:
	if player == null or player.stat_board == null:
		return false
	var mp: PoolStat = player.stat_board.movement_points
	return mp != null and mp.available() >= 1


## Arm or disarm [param upgrade] on the [BladeMode] (#406): re-arming the
## armed card pops it, another card replaces it. Refused (nothing pushed)
## while no blade stands — see [method can_arm_temp_upgrade].
func arm_temp_upgrade(upgrade: TempUpgradeDef) -> void:
	var blade := armed_stack.find(BladeMode) as BladeMode if armed_stack != null else null
	if blade == null:
		return
	var current := armed_stack.find(TempUpgradeMode) as TempUpgradeMode
	if current != null and current.def == upgrade:
		armed_stack.pop(current)
	elif upgrade != null:
		blade.arm_temp_upgrade(upgrade)
	elif current != null:
		armed_stack.pop(current)


## Whether a temp-upgrade card can arm now — owner, 2026-09-30: "Only with a
## blade". The tray's cards read this to show unavailable.
func can_arm_temp_upgrade() -> bool:
	return armed_stack != null and armed_stack.find(BladeMode) != null


func temp_upgrade_arm() -> TempUpgradeDef:
	var level := armed_stack.find(TempUpgradeMode) as TempUpgradeMode if armed_stack != null else null
	return level.def if level != null else null


## Arm a Manage verb card (#338): Deallocate / Stake / Extract switch to their
## level (pop to root, then push), and re-pressing the armed card pops it.
## ALLOCATE and NONE clear to the root — Allocate is the root's native click.
func arm_verb(verb: ManageVerb) -> void:
	if armed_stack == null:
		return
	var current := armed_stack.find(ManageVerbMode) as ManageVerbMode
	match verb:
		ManageVerb.DEALLOCATE, ManageVerb.STAKE, ManageVerb.EXTRACT:
			if current != null and current.verb == verb:
				armed_stack.pop(current)
			else:
				armed_stack.switch_to(_verb_level(verb))
		_:
			armed_stack.clear_to_root()


func _verb_level(verb: ManageVerb) -> ManageVerbMode:
	match verb:
		ManageVerb.DEALLOCATE: return DeallocateMode.new(self)
		ManageVerb.STAKE: return StakeMode.new(self)
		_: return ExtractMode.new(self)


## The armed Manage verb, derived off the branch — compat for
## [HighlightController]; see [signal manage_arm_changed].
func manage_arm() -> ManageVerb:
	var level := armed_stack.find(ManageVerbMode) as ManageVerbMode if armed_stack != null else null
	return level.verb if level != null else ManageVerb.NONE


## Arm an attack mode — the HUD's attack buttons, the melee hotkey, reform.
## Switches (pop to root, then push); the mode already armed is a no-op, not a
## rebuilt plan. A refused request (mid-swing) pushes nothing. Returns whether
## [param mode] is armed afterwards.
func arm_attack(mode: BattleSystem.AttackMode) -> bool:
	if armed_stack == null or battle_system == null:
		return false
	var current := armed_stack.find(AttackArmMode) as AttackArmMode
	if mode == BattleSystem.AttackMode.NONE:
		if current != null:
			armed_stack.pop(current)
		return false
	# Already armed AND still holding its plan: a repeat press keeps the plan.
	# A level whose plan the slot tore down on its own (a launch with no
	# applier to report it) is replaced, not trusted.
	if current != null and current.mode == mode and battle_system.attack_mode == mode:
		return true
	if not can_player_act():
		return false
	return armed_stack.switch_to(_attack_level(mode))


func _attack_level(mode: BattleSystem.AttackMode) -> AttackArmMode:
	match mode:
		BattleSystem.AttackMode.MELEE: return MeleeMode.new(self)
		BattleSystem.AttackMode.RANGED: return RangedMode.new(self)
		_: return MagicMode.new(self)


func pending_mass_action() -> MassActionRequest:
	var level := armed_stack.find(MassActionMode) as MassActionMode if armed_stack != null else null
	return level.request if level != null else null


## Push a pending confirmation on whatever is on top.
func begin_mass_action(request: MassActionRequest) -> void:
	if armed_stack != null:
		armed_stack.push(MassActionMode.new(self, request))


func confirm_mass_action() -> void:
	var level := armed_stack.find(MassActionMode) as MassActionMode if armed_stack != null else null
	if level == null:
		return
	var request := level.request
	var ids: Array[int] = []
	for n in request.nodes:
		ids.append(graph.get_stable_id(n))
	match request.verb:
		MassActionRequest.Verb.ALLOCATE:
			# `affordable_count` stays off the wire — the applier recomputes it
			# from the board it is actually applying against (#458).
			_submit(MassAllocateCommand.new(request.entity.entity_id, ids))
		MassActionRequest.Verb.DEALLOCATE:
			_submit(DeallocateSetCommand.new(request.entity.entity_id, ids))
	armed_stack.pop(level)


## Drop the pending confirmation, back to the level it was pushed on.
func cancel_mass_action() -> void:
	var level := armed_stack.find(MassActionMode) if armed_stack != null else null
	if level != null:
		armed_stack.pop(level)


## The Move Core card: switch to core-move targeting from the player's core,
## or pop it when it is already armed.
func enter_core_move_targeting() -> void:
	if player == null or player.core_location == null or armed_stack == null:
		return
	var current := armed_stack.find(CoreMoveMode)
	if current != null:
		armed_stack.pop(current)
	else:
		armed_stack.switch_to(CoreMoveMode.new(self, player.core_location))


## The one place the stack's single [signal ArmedStack.changed] fans out into
## the controller's derived signals — each only on a real transition.
func _on_armed_stack_changed() -> void:
	var src := move_targeting_source()
	if src != _last_move_source:
		_last_move_source = src
		if src == null:
			_clear_core_drag()
		core_move_targeting_changed.emit(src)
	var upgrade := temp_upgrade_arm()
	if upgrade != _last_temp_upgrade:
		_last_temp_upgrade = upgrade
		temp_upgrade_arm_changed.emit(upgrade)
	var request := pending_mass_action()
	if request != _last_mass_request:
		_last_mass_request = request
		mass_action_pending_changed.emit(request)
	var verb := manage_arm()
	if verb != _last_manage_verb:
		_last_manage_verb = verb
		manage_arm_changed.emit(verb)
	_refresh_armed_state()


func set_input_frozen(frozen: bool) -> void:
	_input_frozen = frozen


func can_player_act() -> bool:
	if not _is_players_turn():
		return false
	# A swing is resolving (#406) — the plan stays live through the live-swing
	# await so its temp-upgrade addons keep rendering, but that's not an
	# invitation to click it mid-swing.
	if battle_system != null and battle_system.is_launching:
		return false
	# A command is mid-application (#510). Nested inside, not merged with,
	# `is_launching`: that flag answers "an attack is in flight" and keeps
	# owning the attack plan's lifetime; this one answers "a command is being
	# applied" and covers every verb, of which the attack is one. A player
	# cannot act while an allocation is landing either, and until now this gate
	# only knew about attacks.
	if command_applier != null and command_applier.is_applying:
		return false
	# A command is submitted and the authority has not decided yet (#541) — the
	# phase BEFORE either of the two above. Locally it is a stack frame wide;
	# on a peer it is the round trip, and it is exactly when a second input
	# would produce a command resolved against a world the player cannot see.
	# Third gate rather than folded into `is_applying`: that flag answers "a
	# mutation is under way", and here nothing has moved yet.
	if command_applier != null and command_applier.is_awaiting_confirmation:
		return false
	# A relic's claim chain is being driven (#646) — offer/pick/roll no longer
	# runs inside `is_applying`, on purpose (issue #646 acceptance 3: it must
	# not hold this applier's queue for a remote human's pick), so the gate
	# that used to fall out of `is_applying` for free has to be explicit here
	# instead. See [CommandApplier.has_outstanding_loot] and the owner's
	# 2026-08-27 pick-gate decision.
	if command_applier != null and command_applier.has_outstanding_loot():
		return false
	# No AP clause: this is the FLOW gate (turn, in-flight command, pending
	# loot). Affordability is per verb — a ranged volley costs 0 AP (#957) and
	# must stay launchable at 0 — so it lives in `can_afford`, not here.
	return true


## The AFFORDABILITY half of the gate: can [member player] pay
## [method AttackPlan.ap_cost] for [param plan] right now? Read beside
## `can_player_act()`, never instead of it; `player_can_act_changed` still
## fires on every AP change so a Launch button can re-ask both.
func can_afford(plan: AttackPlan) -> bool:
	if plan == null or player == null or player.stat_board == null:
		return false
	var ap: PoolStat = player.stat_board.action_points
	return ap == null or ap.available() >= plan.ap_cost()


func on_attack_mode_requested(mode: BattleSystem.AttackMode) -> void:
	arm_attack(mode)


func _emit_gate_changed() -> void:
	player_can_act_changed.emit(can_player_act())
	_refresh_armed_state()


## Hot-seat handover (#459) rides this setter, not a second public entry
## point: `player` is an `@export`, so anything that assigns it directly —
## GameRoot's `bind_player`, a scene's edit-time wiring, a test — has to get
## the transient-state clear too, or player 2 inherits player 1's half-built
## swing.
##
## The no-op skip is exactly that (see the setter-recursion rule): assigning
## the SAME hero must not wipe a live arm, and `bind_player` is documented as
## idempotently re-callable, so it re-asserts the current player routinely.
##
## **The skip covers the transient clear ONLY — never the AP subscription.**
## `Entity._ready` swaps `stat_board` for a `duplicate(true)`, so a scene-wired
## `player` export (dev_sandbox points its NodePath straight at
## `Graph/Entities/Player`) binds this setter to a board the entity then throws
## away. `bind_player`'s idempotent re-assert is what re-binds it to the live
## pool, and a blanket early return silently made that re-assert a no-op: the
## gate then never learns AP was refilled, so the command tray stayed dead for
## the rest of the run after the first turn the player spent AP on.
func _set_player(value: Entity) -> void:
	var changed := player != value
	if changed:
		if player != null and player.stat_board != null:
			var prev_ap: PoolStat = player.stat_board.action_points
			if prev_ap != null and prev_ap.current_changed.is_connected(_on_ap_changed):
				prev_ap.current_changed.disconnect(_on_ap_changed)
		clear_transient_state()
		player = value
		_on_gate_locks_changed()
	# Unconditional. A connection left behind on a board the entity discarded
	# is unreachable from here (`player.stat_board` is the new one) and needs no
	# cleanup — that board is garbage, and its pools die with it.
	if player != null and player.stat_board != null:
		var ap: PoolStat = player.stat_board.action_points
		if ap != null and not ap.current_changed.is_connected(_on_ap_changed):
			ap.current_changed.connect(_on_ap_changed)


## Drop every scrap of half-finished intent: armed modes, the in-flight attack
## plan, mass-action confirmation, core-move targeting and its drag visuals,
## hover/pin, and the modal input freeze. Everything here is state a player
## builds up *during* their turn and that means nothing to the next one.
##
## The freeze is included deliberately: [ModalBase] clears it when its modal
## closes, but a handover that happens while one is up (a loot pick resolving
## into a death, say) would otherwise strand the incoming player with dead
## input and no modal left to unfreeze them.
##
## The attack plan lives on [BattleSystem], not here, so the clear has to reach
## across. A swing mid-resolve (`is_launching`) is left alone — tearing down a
## plan whose landings are still being applied would strand them (see
## [method GameRoot._exit_tree] and the attack-timeline rule); a turn cannot
## end mid-swing anyway, so this is belt-and-braces, not a live path.
##
## Safe before `_ready`: the stack has no root until then, and every call
## below is a no-op on already-default state.
func clear_transient_state() -> void:
	if armed_stack != null and armed_stack.root() != null:
		armed_stack.clear_to_root()
	if battle_system != null and battle_system.is_attacking and not battle_system.is_launching:
		battle_system.cancel_attack()
	_disarm_gate_confirm()
	_clear_core_drag()
	_set_pinned(null)
	_hovered_node = null
	_input_frozen = false
	_refresh_armed_state()


func _on_ap_changed(_new_current: Variant) -> void:
	_emit_gate_changed()


# ── Gates (#1206) ───────────────────────────────────────────────────────────
# Locks are seat-local (GateLockSet); a flip goes out as one ToggleGatesCommand
# naming every gate explicitly. A flip whose preview strands owned nodes arms a
# one-warning confirm first — the identical request again submits it, any other
# gate request disarms it. See docs/design/skill_node_addons.md § Gate.

## Run a bulk gate verb for the current player. Lock verbs only touch the
## seat-local set; the flip verbs expand to the unlocked, toggleable gates in
## the right state (so open-all / close-all are idempotent).
func request_gate_action(action: GateAction) -> void:
	if player == null or graph == null:
		return
	if action == GateAction.LOCK_ALL or action == GateAction.UNLOCK_ALL:
		_disarm_gate_confirm()
		for g in graph.get_gates():
			_gate_locks.set_locked(player, GateLockSet.key_of(graph, g),
					action == GateAction.LOCK_ALL)
		_on_gate_locks_changed()
		return
	var gates: Array[Gate] = []
	for g in toggleable_gates():
		if is_gate_locked(g):
			continue
		if action == GateAction.OPEN_UNLOCKED and g.is_open():
			continue
		if action == GateAction.CLOSE_UNLOCKED and not g.is_open():
			continue
		gates.append(g)
	_request_gate_flip(gates)


## Shift+G: unlock all while anything is locked, else lock all.
func request_gate_locks_hotkey() -> void:
	request_gate_action(GateAction.UNLOCK_ALL if _gate_locks.any_locked(player) \
			else GateAction.LOCK_ALL)


## A span click: flip that one gate, locked or not — the click is deliberate.
## Also the carrier for any surface that names a gate by other means.
func route_gate_click(gate: Gate) -> void:
	if player == null or gate == null or not gate.can_toggle(player):
		return
	var gates: Array[Gate] = [gate]
	_request_gate_flip(gates)


func toggle_gate_lock(gate: Gate) -> void:
	if player == null or gate == null or graph == null:
		return
	_gate_locks.set_locked(player, GateLockSet.key_of(graph, gate), not is_gate_locked(gate))
	_on_gate_locks_changed()


func is_gate_locked(gate: Gate) -> bool:
	return gate != null and graph != null \
			and _gate_locks.is_locked(player, GateLockSet.key_of(graph, gate))


## Every gate the current player may flip right now.
func toggleable_gates() -> Array[Gate]:
	var out: Array[Gate] = []
	if player == null or graph == null:
		return out
	for g in graph.get_gates():
		if g.can_toggle(player):
			out.append(g)
	return out


## The owned nodes the armed gate flip would strand; empty when nothing is armed.
func pending_gate_strand() -> Array[SkillNode]:
	return _gate_pending_strand


func cancel_gate_confirm() -> void:
	_disarm_gate_confirm()


func _request_gate_flip(gates: Array[Gate]) -> void:
	if gates.is_empty():
		_disarm_gate_confirm()
		return
	var key := _gate_request_key(gates)
	if not _gate_pending_strand.is_empty() and key == _gate_pending_key:
		_disarm_gate_confirm()
		_submit_gate_flip(gates)
		return
	_disarm_gate_confirm()
	var stranded := allocation_system.gate_flip_cascade(gates, player) \
			if allocation_system != null else [] as Array[SkillNode]
	if stranded.is_empty():
		_submit_gate_flip(gates)
		return
	_gate_pending_key = key
	_gate_pending_strand = stranded
	gate_confirm_changed.emit(_gate_pending_strand)


func _submit_gate_flip(gates: Array[Gate]) -> void:
	var pairs: Array[int] = []
	for g in gates:
		pairs.append(graph.get_stable_id(g.from))
		pairs.append(graph.get_stable_id(g.to))
	_submit(ToggleGatesCommand.new(player.entity_id, pairs))


func _gate_request_key(gates: Array[Gate]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for g in gates:
		out.append(GateLockSet.key_of(graph, g))
	out.sort()
	return out


func _disarm_gate_confirm() -> void:
	_gate_pending_key = []
	if _gate_pending_strand.is_empty():
		return
	_gate_pending_strand = []
	gate_confirm_changed.emit(_gate_pending_strand)


func _on_gate_locks_changed() -> void:
	if graph != null:
		for g in graph.get_gates():
			g.set_locked_display(is_gate_locked(g))
	gate_locks_changed.emit()


func _on_gate_added(child: Node) -> void:
	var gate := child as Gate
	if gate == null:
		return
	if not gate.span_clicked.is_connected(_on_gate_span_clicked):
		gate.span_clicked.connect(_on_gate_span_clicked)
	if graph != null and gate.from != null and gate.to != null:
		gate.set_locked_display(is_gate_locked(gate))


## A node disc wins over a span it overlaps: a click while a node is hovered
## belongs to the node.
func _on_gate_span_clicked(gate: Gate, button: MouseButton) -> void:
	if _input_frozen or _hovered_node != null or not _is_players_turn():
		return
	if button == MOUSE_BUTTON_LEFT:
		route_gate_click(gate)
	elif button == MOUSE_BUTTON_RIGHT:
		toggle_gate_lock(gate)
