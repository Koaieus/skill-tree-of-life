@tool
class_name HudRoot
extends Control

## Structural spine of the "Arcane Terminal" HUD (#98/#107) — the sole UI
## layer since #118's cutover (replaced the old UIRoot). Anchors the five
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
@onready var action_cluster: ActionCluster = %ActionCluster
@onready var command_tray: CommandTray = %CommandTray
@onready var announcement_layer: AnnouncementLayer = %AnnouncementLayer
@onready var stat_board_overlay: StatBoardOverlay = %StatBoardOverlay
@onready var loot_picker: LootPicker = %LootPicker

var _player: Entity
var _input_ctl: PlayerInputController
var _battle_system: BattleSystem
var _turn_manager: TurnManager
var _vision_system: VisionSystem


func _ready() -> void:
	# Loot picks route over the global bus; the handler filters to the player
	# (set in compose, well before any relic is claimed in play). Runtime only —
	# the editor @tool pass has no player and no live combat.
	if not Engine.is_editor_hint():
		Events.loot_pick_requested.connect(_on_loot_pick_requested)


## Injected by [GameRoot] once it and HudRoot are both in the tree. Every
## `source.signal.connect(target)` is paired with an immediate call using
## the source's current value.
func compose(game_root: GameRoot) -> void:
	_player = game_root.player
	_input_ctl = game_root.input_ctl
	_battle_system = game_root.battle_system
	_turn_manager = game_root.turn_manager
	_vision_system = game_root.vision_system

	if _player == null:
		return

	if stat_board_overlay != null:
		stat_board_overlay.board = _player.stat_board
	if hero_sigil_card != null:
		hero_sigil_card.bind(_player)
	if attributes_panel != null:
		attributes_panel.bind(_player.stat_board)
	if turn_resources_panel != null:
		turn_resources_panel.bind(_player.stat_board)
		turn_resources_panel.bind_input_ctl(_input_ctl)
	if combat_readout != null:
		combat_readout.bind(_player, _battle_system)
	if node_inspector_card != null:
		node_inspector_card.bind(_input_ctl)
	if action_cluster != null:
		action_cluster.bind(_player, _turn_manager, _input_ctl, _vision_system)
	if command_tray != null:
		command_tray.bind(_turn_manager, _battle_system, _input_ctl, _player)
	if announcement_layer != null:
		announcement_layer.bind(_battle_system)
	_bind_announcement_layer()
	_bind_initiative_bar()


## Pick-N-from-M loot claim (#173). Only the PLAYER's relics get the picker —
## claim `handled` SYNCHRONOUSLY (before emit() returns) so SkillDustAddon won't
## auto-resolve behind us; NPC relics fall through untouched to their auto-pick.
func _on_loot_pick_requested(request: LootPickRequest) -> void:
	if loot_picker == null or _player == null or request.collector != _player:
		return
	request.handled = true
	loot_picker.present(request)


## Ports UIRoot's banner routing (#118 cutover parity) — "YOUR TURN" on the
## player's turn start, "LEVEL UP" on level-up. AI turns animate silently.
func _bind_announcement_layer() -> void:
	if announcement_layer == null or _turn_manager == null or _player == null:
		return
	announcement_layer.bind_turn_manager(_turn_manager)
	_turn_manager.turn_started.connect(_on_turn_started_for_banner)
	if not _player.leveled_up.is_connected(_on_player_leveled_up):
		_player.leveled_up.connect(_on_player_leveled_up)


func _on_turn_started_for_banner(entity: Entity) -> void:
	if entity == _player:
		announcement_layer.enqueue(AnnouncementRequest.make_for_entity(
				"YOUR TURN", "", AnnouncementRequest.Style.DEFAULT, entity))


func _on_player_leveled_up(new_level: int) -> void:
	announcement_layer.enqueue(LevelUpAnnouncementRequest.make_for_level_up(
			_player, 1, new_level))


## #116 — Turn Tracker Pill. InitiativeBar already implements the "hide
## during MY turn, show + climb otherwise" behavior UIRoot relies on
## (_on_owner_turn_started slides it out, _on_owner_turn_ended slides it
## back in) — reused verbatim, just wired the same way UIRoot.compose()
## wires its own copy.
func _bind_initiative_bar() -> void:
	if initiative_bar == null or _player == null or _player.stat_board == null or _turn_manager == null:
		return
	var init_pool := _player.stat_board.initiative
	if init_pool == null:
		return
	initiative_bar.max_initiative = float(init_pool.value)
	init_pool.current_changed.connect(initiative_bar._on_initiative_changed)
	init_pool.replenished.connect(initiative_bar._on_ready)
	initiative_bar._on_initiative_changed(float(init_pool.current))
	_turn_manager.turn_started.connect(_on_turn_started_for_initiative)
	_turn_manager.turn_ended.connect(_on_turn_ended_for_initiative)


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
