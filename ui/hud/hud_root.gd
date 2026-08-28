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
@onready var run_end_overlay: RunEndOverlay = %RunEndOverlay
@onready var pause_menu: PauseMenu = %PauseMenu
@onready var tooltip_fan: TooltipFan = %TooltipFan
@onready var gained_modifier_toast: GainedModifierToast = %GainedModifierToast
@onready var minimap_panel: MinimapPanel = %MinimapPanel

var _player: Entity
## The composition root, kept only to read [member GameRoot.seat_policy] when a
## run ends (#517). Deliberately the ROOT and not the policy: `game_root.gd`
## initialises a default couch policy at field-init and a roster REPLACES the
## object during `_setup_level`, so a policy cached in [method bind_systems]
## can be the stale pre-roster instance. Optional — a hand-built HUD fixture
## has none, and then the run-end overlay simply behaves like a couch.
var _game_root: GameRoot
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
## cluster that made it. Cleared on rebind, same as each cluster's own scope.
## A [SubBag], not a bare [BindScope]: the initiative readout needs the same
## "connect now, paint now" `now()` fuses (#9) that the manual link-then-call
## below used to spell out by hand.
var _binds := SubBag.new()


func _ready() -> void:
	# Loot picks route over the global bus; the handler filters to the player
	# (set in compose, well before any relic is claimed in play). Runtime only —
	# the editor @tool pass has no player and no live combat.
	if not Engine.is_editor_hint():
		Events.loot_pick_requested.connect(_on_loot_pick_requested)
		Events.spell_loot_requested.connect(_on_spell_loot_requested)
		Events.run_ended.connect(_on_run_ended)
		# The overlay asks to leave; GameRoot decides whether it may (#526).
		if run_end_overlay != null:
			run_end_overlay.main_menu_pressed.connect(_on_run_end_main_menu_pressed)
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
			game_root.turn_manager, game_root.vision_system, game_root.allocation_system,
			game_root)
	rebind_player(game_root.player)


## The system-lifetime half of [method compose] — everything keyed to the
## level rather than to whoever currently holds the turn. Runs once; a second
## call is a no-op beyond re-caching the references (see [member
## _systems_bound]).
##
## Takes the systems rather than the [GameRoot] that owns them so the HUD's
## rebind seam can be exercised against hand-built systems, without a live
## composition root — the same reason [method GameRoot.apply_roster] is static.
## [param game_root] is the one exception and stays OPTIONAL for that reason:
## the run-end overlay needs a [SeatPolicy] and only the root has one (see
## [member _game_root]).
func bind_systems(
	graph: Graph,
	input_ctl: PlayerInputController,
	battle_system: BattleSystem,
	turn_manager: TurnManager,
	vision_system: VisionSystem,
	allocation_system: AllocationSystem,
	game_root: GameRoot = null,
) -> void:
	_game_root = game_root
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
	# The camera comes off the ROOT, not the systems list, because it is not a
	# system in that list's sense — same exception `_game_root` already exists
	# for. A HUD fixture with no root simply gets a null camera and the minimap
	# draws its board without a viewport outline.
	if minimap_panel != null:
		minimap_panel.bind(graph,
				game_root.camera if game_root != null else null, _allocation_system)
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
	_binds.clear()
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
## player's turn start. AI turns animate silently. LEVEL UP is deliberately NOT
## here: it belongs to the XP bar, which owns the replay queue and is therefore
## the only thing that knows when a cascade is done ([LevelUpFlourish], #320).
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
	if initiative_bar != null:
		_turn_manager.turn_started.connect(_on_turn_started_for_initiative)
		_turn_manager.turn_ended.connect(_on_turn_ended_for_initiative)


func _on_turn_started_for_banner(entity: Entity) -> void:
	if entity == _player:
		announcement_layer.enqueue(AnnouncementRequest.make_for_entity(
				"YOUR TURN", "", AnnouncementRequest.Style.DEFAULT, entity))


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
	# now(): connect-and-paint fused into one call — the manual link-then-call
	# this replaced was exactly the read/subscribe gap SubBag exists to close.
	# The default arg is load-bearing: `now()` invokes this with zero arguments
	# for the synchronous first paint, while `current_changed` itself emits one
	# — the lambda has to tolerate both calling conventions, so it re-reads
	# `init_pool.current` rather than trust either call's argument.
	_binds.now(init_pool.current_changed,
			func(_v: float = 0.0) -> void:
				initiative_bar._on_initiative_changed(float(init_pool.current)))
	_binds.on(init_pool.replenished, initiative_bar._on_ready)


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


## The run ended (#517). The HUD is where a POV-free [RunOutcome] becomes a
## local reading, because the point of view is a fact about this MACHINE — the
## outcome names one winner and every screen watching may narrate it
## differently.
##
## Two separate presentations, deliberately not one:
## - **The banner is camp-authored, never entity-authored.** Text and tint come
##   from [member RunOutcome.winning_camp] alone, so a camp holding two living
##   heroes announces once, as a camp. Plural phrasing ("Players win!" for coop)
##   is then an AUTHORING choice in the faction `.tres`, not a code branch.
## - **The overlay always comes up** (#526) — it is the run's way OUT of the
##   level, so gating it would strand a couch and a draw. [SeatPolicy] picks its
##   copy instead; see [method _run_end_reading].
##
## [method AnnouncementLayer.enqueue_now] and not `enqueue`: this is the last
## thing the run has to say, so it preempts the TITLE band rather than waiting
## behind the killing blow's own kill toast. That toast IS stomped mid-play —
## deliberately; nothing queued before the end of the run outranks it.
func _on_run_ended(outcome: RunOutcome) -> void:
	if outcome == null:
		return
	if announcement_layer != null:
		announcement_layer.enqueue_now(_run_end_banner(outcome))
	if run_end_overlay != null:
		run_end_overlay.present(_run_end_reading(outcome), outcome.winning_camp)


func _run_end_banner(outcome: RunOutcome) -> AnnouncementRequest:
	var camp := outcome.winning_camp
	if camp == null:
		return AnnouncementRequest.make("DRAW", "", AnnouncementRequest.Style.DEATH)
	return AnnouncementRequest.make_tinted(
			"%s wins!" % camp.display_name, "", camp.color,
			AnnouncementRequest.Style.LEVEL_UP)


## How does THIS screen read the run's end? Resolved from seating, not from the
## bound hero — which is the whole fix (#517): `rebind_player` fires on every
## hot-seat handover (#459), so anything derived from "the current player"
## answered from whoever acted last.
##
## The reading decides the overlay's COPY only. Since #526 the overlay itself is
## unconditional — it carries the way out of the level, and a couch or a draw
## needs that as much as a defeated seat does.
##
## - **DRAW** — nobody won; there is no camp to read it against.
## - **COUCH** — neutral, ever. Two rivals share one screen, so there is no camp
##   for this screen to have lost from. That is what makes the reading
##   independent of turn order.
## - **SEAT** — one human, one machine, one hero: victory iff that hero's camp
##   won. Reading [member _player] is legitimate *here specifically* because
##   [method SeatPolicy.follows_active_turn] is false under SEAT, so
##   [method GameRoot._on_turn_started_for_handover] never re-points the player
##   and `_player` IS the seated hero — including after it dies, which is
##   exactly when this matters and when walking [constant Entity.GROUP] for it
##   would fail (GameRoot pulls corpses out of that group synchronously).
func _run_end_reading(outcome: RunOutcome) -> RunEndOverlay.Reading:
	if outcome.winning_camp == null:
		return RunEndOverlay.Reading.DRAW
	var policy: SeatPolicy = _game_root.seat_policy if _game_root != null else null
	if policy == null or policy.seating != SeatPolicy.Seating.SEAT:
		return RunEndOverlay.Reading.NEUTRAL
	var camp: Faction = _player.faction if _player != null else null
	if camp == null or camp.id == &"":
		return RunEndOverlay.Reading.NEUTRAL
	return (RunEndOverlay.Reading.VICTORY if camp.id == outcome.winning_camp.id
			else RunEndOverlay.Reading.DEFEAT)


## The overlay never routes itself — [GameRoot] owns the way out, including the
## `route_to_meta_on_run_end` veto that keeps a neutered root in its own scene.
##
## Where that veto bites (both dev sandboxes set it), the press still has to do
## SOMETHING: a full-screen dim with a dead button, over a level you were about
## to keep poking at, is worse than the banner-only run-end it replaced. So the
## one action means "get me out of here" and settles for the overlay when it
## cannot have the level.
func _on_run_end_main_menu_pressed() -> void:
	if _game_root != null and _game_root.route_to_meta_now():
		return
	if run_end_overlay != null:
		run_end_overlay.dismiss()
