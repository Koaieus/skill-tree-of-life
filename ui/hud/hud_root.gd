@tool
class_name HudRoot
extends Control

## Structural spine of the "Arcane Terminal" HUD (#98/#107) — the replacement
## for [UIRoot]. Anchors the five design clusters via Control anchor presets
## + margins (translated from the design's 1440x900 absolute coords, not
## hardcoded pixel offsets) and hands cross-system deps to each cluster's
## own scene-local `bind()`/setter, mirroring [UIRoot.compose]'s DI contract:
## scene-local children via `%UniqueName`, cross-system deps via one
## `compose(game_root)` call from GameRoot.
##
## Composed side-by-side with UIRoot during the build-out (#107..#117) —
## GameRoot composes both; only #118 (Cutover) swaps which one is visible.
## Phase 5/6 slots (command tray, AP+End Turn cluster) are empty anchors
## until their issues land.

@onready var turn_tracker_slot: Control = %TurnTrackerSlot
@onready var left_column_slot: Control = %LeftColumnSlot
@onready var right_column_slot: Control = %RightColumnSlot
@onready var command_tray_slot: Control = %CommandTraySlot
@onready var ap_end_turn_slot: Control = %APEndTurnSlot

@onready var hero_sigil_card: HeroSigilCard = %HeroSigilCard
@onready var attributes_panel: AttributesPanel = %AttributesPanel
@onready var turn_resources_panel: TurnResourcesPanel = %TurnResourcesPanel
@onready var combat_readout: CombatReadout = %CombatReadout

var _player: Entity
var _input_ctl: PlayerInputController
var _battle_system: BattleSystem
var _turn_manager: TurnManager
var _vision_system: VisionSystem


## Injected by [GameRoot] once it and HudRoot are both in the tree. Same
## discipline as [UIRoot.compose]: every `source.signal.connect(target)` is
## paired with an immediate call using the source's current value.
func compose(game_root: GameRoot) -> void:
	_player = game_root.player
	_input_ctl = game_root.input_ctl
	_battle_system = game_root.battle_system
	_turn_manager = game_root.turn_manager
	_vision_system = game_root.vision_system

	if _player == null:
		return

	if hero_sigil_card != null:
		hero_sigil_card.bind(_player)
	if attributes_panel != null:
		attributes_panel.bind(_player.stat_board)
	if turn_resources_panel != null:
		turn_resources_panel.bind(_player.stat_board)
	if combat_readout != null:
		combat_readout.bind(_player, _battle_system)
