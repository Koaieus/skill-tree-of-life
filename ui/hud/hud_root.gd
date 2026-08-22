@tool
class_name HudRoot
extends Control

## Structural spine of the "Arcane Terminal" HUD (#98/#107) — the sole UI
## layer since #118's cutover (replaced the old UIRoot). Anchors the six
## design clusters via Control anchor presets + margins (translated from the
## design's 1440x900 absolute coords, not hardcoded pixel offsets) and hands
## cross-system deps to each cluster's own scene-local `bind()`/setter:
## scene-local children via `%UniqueName`, cross-system deps via one
## `compose(game_root)` call from GameRoot.

@onready var turn_tracker_slot: Control = %TurnTrackerSlot
@onready var left_column_slot: Control = %LeftColumnSlot
@onready var right_column_slot: Control = %RightColumnSlot
@onready var command_tray_slot: Control = %CommandTraySlot
@onready var ap_end_turn_slot: Control = %APEndTurnSlot

@onready var hero_sigil_card: HeroSigilCard = %HeroSigilCard
@onready var attributes_panel: AttributesPanel = %AttributesPanel
@onready var turn_resources_panel: TurnResourcesPanel = %TurnResourcesPanel
@onready var combat_readout: CombatReadout = %CombatReadout
@onready var node_inspector_card: NodeInspectorCard = %NodeInspectorCard
@onready var initiative_bar: InitiativeBar = %InitiativeBar
@onready var xp_track: XpTrack = %XpTrack
@onready var action_cluster: ActionCluster = %ActionCluster
@onready var command_tray: CommandTray = %CommandTray
@onready var announcement_layer: AnnouncementLayer = %AnnouncementLayer
@onready var armed_mode_glow: ArmedModeGlow = %ArmedModeGlow
@onready var stat_board_overlay: StatBoardOverlay = %StatBoardOverlay
@onready var loot_picker: LootPicker = %LootPicker
@onready var mass_action_confirm_panel: MassActionConfirmPanel = %MassActionConfirmPanel
@onready var spell_loot_picker: SpellLootPicker = %SpellLootPicker
@onready var game_over_overlay: CanvasLayer = %GameOverOverlay
@onready var pause_menu: PauseMenu = %PauseMenu
@onready var tooltip_fan: TooltipFan = %TooltipFan
@onready var gained_modifier_toast: GainedModifierToast = %GainedModifierToast

var _player: Entity
var _input_ctl: PlayerInputController
var _battle_system: BattleSystem
var _turn_manager: TurnManager
var _vision_system: VisionSystem
var _allocation_system: AllocationSystem

## Pending-modal queue (#204/#486): ONE [ModalBase] is up at a time, ever.
## A kill can fire BOTH the dust pick and the spell draft synchronously (both
## routed off `Events.entity_dying` inside LootSystem), and a second `present()`
## would just stomp the first's cards — worse, since #486 traded the tree pause
## for `set_input_frozen` (a plain bool, not a counter), two overlapping modals
## would leave the first one to close unfreezing input under the second.
## Serializing here is what keeps that bool honest, so EVERY modal goes through
## this queue, not just the pickers.
##
## Each entry is a zero-arg Callable that shows one request; `_drain_modals`
## shows the next only once the current modal's `closed` signal fires. Dust
## always queues before the spell draft because LootSystem dispatches
## `_drop_skill_dust` before `_award_spell_loot`.
var _pending_modals: Array[Callable] = []
var _modal_busy: bool = false

## Latch for the system-lifetime half of [method compose]. Everything keyed to
## a SYSTEM (the level's turn manager, battle system, hover bus) is wired once;
## everything keyed to the PLAYER re-points on every hot-seat handover (#459).
## Without the split, `rebind_player` would re-run `turn_manager.turn_started`
## connections and each banner/gate would fire once per handover so far.
var _systems_bound: bool = false

## What HudRoot itself connects to the CURRENT hero's pools — just the
## initiative bar, since every other player-keyed connection belongs to the
## cluster that made it. Released on rebind, same as each cluster's own scope.
var _binds := BindScope.new()


func _ready() -> void:
	# Loot picks route over the global bus; the handler filters to the player
	# (set in compose, well before any relic is claimed in play). Runtime only —
	# the editor @tool pass has no player and no live combat.
	if not Engine.is_editor_hint():
		Events.loot_pick_requested.connect(_on_loot_pick_requested)
		Events.spell_loot_requested.connect(_on_spell_loot_requested)
		Events.game_over.connect(_on_game_over)
		if loot_picker != null:
			loot_picker.closed.connect(_on_modal_closed)
		if spell_loot_picker != null:
			spell_loot_picker.closed.connect(_on_modal_closed)
		if mass_action_confirm_panel != null:
			mass_action_confirm_panel.closed.connect(_on_modal_closed)


## Let go of the hero's board when the level goes away. A Stat is a Resource
## and outlives the Control that was listening to it, so a HUD freed while
## still bound leaves lambdas holding freed gauges — which fire, loudly, the
## next time that pool changes. Symmetric with [method rebind_player].
func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	rebind_player(null)


## Injected by [GameRoot] once it and HudRoot are both in the tree. Every
## `source.signal.connect(target)` is paired with an immediate call using
## the source's current value.
func compose(game_root: GameRoot) -> void:
	bind_systems(game_root.graph, game_root.input_ctl, game_root.battle_system,
			game_root.turn_manager, game_root.vision_system, game_root.allocation_system)
	rebind_player(game_root.player)


## The system-lifetime half of [method compose] — everything keyed to the
## level rather than to whoever currently holds the turn. Runs once; a second
## call is a no-op beyond re-caching the references (see [member
## _systems_bound]).
##
## Takes the systems rather than the [GameRoot] that owns them so the HUD's
## rebind seam can be exercised against hand-built systems, without a live
## composition root — the same reason [method GameRoot.apply_roster] is static.
func bind_systems(
	graph: Graph,
	input_ctl: PlayerInputController,
	battle_system: BattleSystem,
	turn_manager: TurnManager,
	vision_system: VisionSystem,
	allocation_system: AllocationSystem,
) -> void:
	_input_ctl = input_ctl
	_battle_system = battle_system
	_turn_manager = turn_manager
	_vision_system = vision_system
	_allocation_system = allocation_system
	if _systems_bound:
		return
	_systems_bound = true

	# The fan is hover-driven and renders for unowned nodes too, so it stays
	# useful in a level with no player entity.
	if tooltip_fan != null:
		tooltip_fan.bind(graph)
	# The glow reads the input controller, not the player, and a level with no
	# player entity simply never arms anything.
	if armed_mode_glow != null:
		armed_mode_glow.bind(_input_ctl)
	if node_inspector_card != null:
		node_inspector_card.bind(_input_ctl)
	if turn_resources_panel != null:
		turn_resources_panel.bind_input_ctl(_input_ctl)
	if combat_readout != null:
		combat_readout.bind(_battle_system)
	if action_cluster != null:
		action_cluster.bind(_turn_manager, _input_ctl, _vision_system)
	if command_tray != null:
		command_tray.bind(_battle_system, _input_ctl)
	if announcement_layer != null:
		announcement_layer.bind(_battle_system)
	if loot_picker != null:
		loot_picker.bind(_input_ctl)
	if spell_loot_picker != null:
		spell_loot_picker.bind(_input_ctl)
	# The allocation system is the panel's affordability oracle, not its
	# trigger — a level without one still shows the confirm (dimmed), rather
	# than arming a request no surface ever presents.
	if mass_action_confirm_panel != null:
		mass_action_confirm_panel.bind_systems(_input_ctl, _allocation_system)
		if _input_ctl != null:
			_input_ctl.mass_action_pending_changed.connect(_on_mass_action_pending_changed)
	if xp_track != null and hero_sigil_card != null:
		# The emblem badge is the card's, but the beat that bumps it is the XP
		# bar's — one source for badge, banner and gauge (#317/#320). It rides
		# `level_display_changed`, not `level_reached`, so a level granted outside
		# the XP pool still reaches the badge (see XpTrack's signal docs).
		xp_track.level_display_changed.connect(hero_sigil_card.show_level)
	_bind_turn_signals()


## Re-point every player-keyed cluster at [param player]. Called by [method
## compose] with the level's initial hero, and again on every hot-seat
## handover (#459) by [method GameRoot.bind_player].
##
## Each cluster releases its own previous connections (see [BindScope]) —
## this method only decides WHO, never bookkeeps the how. Null-safe: a level
## with no player entity leaves the clusters unbound, exactly as before.
func rebind_player(player: Entity) -> void:
	if not _systems_bound:
		# GameRoot binds the player once before HudRoot.compose runs (see its
		# `_ready`); the compose call that follows does this properly.
		return
	_binds.release()
	_player = player
	var board: StatBoard = _player.stat_board if _player != null else null

	# Null is a real argument, not a bail-out: it is how the HUD lets go of a
	# board entirely (level teardown, see `_exit_tree`). Every binder below
	# releases its own scope first and then handles a null gracefully, so
	# passing it through is what makes "bound to nobody" reachable.
	if stat_board_overlay != null:
		stat_board_overlay.board = board
	if hero_sigil_card != null:
		hero_sigil_card.bind(_player)
		if _player != null:
			hero_sigil_card.show_level(_player.level)
	if xp_track != null:
		xp_track.bind(_player)
	if attributes_panel != null:
		attributes_panel.bind(board)
	if turn_resources_panel != null:
		turn_resources_panel.bind(board)
	if combat_readout != null:
		combat_readout.set_player(_player)
	if action_cluster != null:
		action_cluster.set_player(_player)
	if command_tray != null:
		command_tray.set_player(_player)
	_bind_initiative_pool()


## Pick-1-of-M loot claim (#173). Only the PLAYER's relics get the picker — set
## `claim` SYNCHRONOUSLY (before emit() returns) so SkillDustAddon won't
## auto-resolve behind us; NPC relics fall through untouched to their auto-pick.
## `LOCAL` specifically: the tri-state exists to keep this case distinguishable
## from a REMOTE human's pick, which no HUD on this machine can present (#522).
func _on_loot_pick_requested(request: LootPickRequest) -> void:
	if loot_picker == null or _player == null or request.collector != _player:
		return
	request.claim = LootPickRequest.Claim.LOCAL
	_enqueue_modal(func() -> void: loot_picker.present(request))


## Pick-1-from-M spell draft (#204). Same filter + handshake as the dust pick
## above, queued behind it (see `_pending_modals`).
func _on_spell_loot_requested(request: SpellLootRequest) -> void:
	if spell_loot_picker == null or _player == null or request.collector != _player:
		return
	request.claim = SpellLootRequest.Claim.LOCAL
	_enqueue_modal(func() -> void: spell_loot_picker.present(request))


## The mass allocate-path / deallocate-cascade confirm (#486). Unlike the loot
## picks this request has a LIVE lifetime on PlayerInputController — it can be
## revoked from outside the modal (`clear_transient_state` on level teardown),
## which is what the null branch is: take the panel down without answering,
## which still unfreezes input and still drains the queue.
func _on_mass_action_pending_changed(request: MassActionRequest) -> void:
	if mass_action_confirm_panel == null:
		return
	if request == null:
		mass_action_confirm_panel.dismiss()
		return
	_enqueue_modal(func() -> void: mass_action_confirm_panel.present(request))


func _enqueue_modal(show_request: Callable) -> void:
	_pending_modals.append(show_request)
	_drain_modals()


func _drain_modals() -> void:
	if _modal_busy or _pending_modals.is_empty():
		return
	_set_modal_busy(true)
	var show_request: Callable = _pending_modals.pop_front()
	show_request.call()


func _on_modal_closed() -> void:
	_set_modal_busy(false)
	_drain_modals()


## A modal is up/down (#486) — beyond the queue flag itself, this also gates
## AnnouncementLayer (a Tween-driven banner must not draw over a frozen, dimmed
## modal) and PauseMenu (Esc must not open the pause menu on top of one).
func _set_modal_busy(busy: bool) -> void:
	_modal_busy = busy
	if announcement_layer != null:
		announcement_layer.set_modal_open(busy)
	if pause_menu != null:
		pause_menu.set_blocked(busy)


## Ports UIRoot's banner routing (#118 cutover parity) — "YOUR TURN" on the
## player's turn start, "LEVEL UP" on level-up. AI turns animate silently.
## Also the initiative bar's show/hide beats.
##
## System-lifetime, despite every handler comparing against `_player`: the
## SIGNAL is the turn manager's, and the handlers re-read `_player` when they
## fire, so a handover needs no rewiring here. This used to bail on a null
## player and was re-entered per compose — it is now connected exactly once,
## before the first player is ever bound.
func _bind_turn_signals() -> void:
	if _turn_manager == null:
		return
	if announcement_layer != null:
		announcement_layer.bind_turn_manager(_turn_manager)
		_turn_manager.turn_started.connect(_on_turn_started_for_banner)
	# LEVEL UP is paced by the XP bar, not by the model (#317). `Entity.leveled_up`
	# fires the instant XP lands — every level of a cascade in the same frame, and
	# seconds before the bar has finished telling that story. XpTrack's
	# `level_reached` is the same fact, emitted once per level at the moment the
	# gauge actually reaches full.
	if xp_track != null and not xp_track.level_reached.is_connected(_on_level_reached):
		xp_track.level_reached.connect(_on_level_reached)
	if initiative_bar != null:
		_turn_manager.turn_started.connect(_on_turn_started_for_initiative)
		_turn_manager.turn_ended.connect(_on_turn_ended_for_initiative)


func _on_turn_started_for_banner(entity: Entity) -> void:
	if entity == _player:
		announcement_layer.enqueue(AnnouncementRequest.make_for_entity(
				"YOUR TURN", "", AnnouncementRequest.Style.DEFAULT, entity))


func _on_level_reached(new_level: int) -> void:
	announcement_layer.enqueue(LevelUpAnnouncementRequest.make_for_level_up(
			_player, 1, new_level))


## #116 — Turn Tracker Pill. InitiativeBar already implements the "hide
## during MY turn, show + climb otherwise" behavior UIRoot relies on
## (_on_owner_turn_started slides it out, _on_owner_turn_ended slides it
## back in) — reused verbatim, just wired the same way UIRoot.compose()
## wires its own copy.
##
## The bar's own turn-manager beats are system-lifetime and live in
## [method _bind_turn_signals]; only the POOL is per-player, so only the pool
## is re-linked here.
func _bind_initiative_pool() -> void:
	if initiative_bar == null or _player == null or _player.stat_board == null:
		return
	var init_pool := _player.stat_board.initiative
	if init_pool == null:
		return
	initiative_bar.max_initiative = float(init_pool.value)
	_binds.link(init_pool.current_changed, initiative_bar._on_initiative_changed)
	_binds.link(init_pool.replenished, initiative_bar._on_ready)
	initiative_bar._on_initiative_changed(float(init_pool.current))


func _on_turn_started_for_initiative(entity: Entity) -> void:
	if entity == _player:
		var init_pool := _player.stat_board.initiative if _player.stat_board != null else null
		if init_pool != null:
			initiative_bar._on_owner_turn_started(float(init_pool.current))


func _on_turn_ended_for_initiative(entity: Entity) -> void:
	if entity == _player:
		var init_pool := _player.stat_board.initiative if _player.stat_board != null else null
		if init_pool != null:
			initiative_bar._on_owner_turn_ended(float(init_pool.current))


func _on_game_over() -> void:
	if game_over_overlay != null:
		game_over_overlay.visible = true
