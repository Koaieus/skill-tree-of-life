@tool
class_name CombatReadout
extends VBoxContainer
## Right column shell (#111): 4-card vertical container (Melee/Ranged/Magic/
## Defense) with mode-highlight binding. The card matching
## [member BattleSystem.attack_plan]'s mode gets the glow border; others dim.
## Owns the transient "un-mute even if not selected" logic — child cards
## just render values and expose [method CombatReadoutCard.flash_unmute].
##
## Mode selection is read off [BattleSystem.attack_plan_changed] (the same
## source [AttackModeBar]/[PlayerInputController] already drive) — not a
## second mode-tracking source of truth.

@onready var _melee_card: CombatCardMelee = %MeleeCard
@onready var _ranged_card: CombatCardRanged = %RangedCard
@onready var _magic_card: CombatCardMagic = %MagicCard
@onready var _defense_card: CombatCardDefense = %DefenseCard

var _battle_system: BattleSystem


func bind(player: Entity, battle_system: BattleSystem) -> void:
	_battle_system = battle_system
	var board := player.stat_board if player != null else null

	_melee_card.bind(board)
	_ranged_card.bind(board)
	_defense_card.bind(board)
	if _battle_system != null:
		_magic_card.bind(_battle_system)
		_battle_system.attack_plan_changed.connect(_on_plan_changed)
		_on_plan_changed(_battle_system.attack_plan)

	if board != null:
		if board.blade_size != null:
			board.blade_size.value_changed.connect(_melee_card.flash_unmute)
		if board.blade_damage != null:
			board.blade_damage.value_changed.connect(_melee_card.flash_unmute)
		if board.range != null:
			board.range.value_changed.connect(_ranged_card.flash_unmute)
		if board.armor != null:
			board.armor.value_changed.connect(_defense_card.flash_unmute)


func _on_plan_changed(plan: AttackPlan) -> void:
	var mode := plan.mode if plan != null else BattleSystem.AttackMode.NONE
	_melee_card.set_active(mode == BattleSystem.AttackMode.MELEE)
	_ranged_card.set_active(mode == BattleSystem.AttackMode.RANGED)
	_magic_card.set_active(mode == BattleSystem.AttackMode.MAGIC)
	_defense_card.set_active(false)
