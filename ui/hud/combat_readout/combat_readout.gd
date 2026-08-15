@tool
class_name CombatReadout
extends VBoxContainer
## Right column shell (#111): 5-card vertical container (Melee/Ranged/Magic/
## Crit/Defense) with mode-highlight binding. The card matching
## [member BattleSystem.attack_plan]'s mode gets the glow border; others dim.
## Owns the transient "un-mute even if not selected" logic — child cards
## just render values and expose [method CombatReadoutCard.flash_unmute].
##
## Mode selection is read off [BattleSystem.attack_plan_changed] (the same
## source [AttackModeBar]/[PlayerInputController] already drive) — not a
## second mode-tracking source of truth.
##
## #119 — also owns the node-local stat override preview: subscribes to the
## global hover bus (Events.skill_node_hovered/unhovered — the same source
## TooltipFan/DebugClipboard already use) and forwards the hovered
## node to the three stat-bearing cards, gated to nodes owned by the bound
## player (see CombatReadoutCard._local_override_or_null).

@onready var _melee_card: CombatCardMelee = %MeleeCard
@onready var _ranged_card: CombatCardRanged = %RangedCard
@onready var _magic_card: CombatCardMagic = %MagicCard
@onready var _crit_card: CombatCardCrit = %CritCard
@onready var _defense_card: CombatCardDefense = %DefenseCard

var _battle_system: BattleSystem
var _player: Entity


func bind(player: Entity, battle_system: BattleSystem) -> void:
	_battle_system = battle_system
	_player = player
	var board := player.stat_board if player != null else null

	if _battle_system != null:
		# Inject battle system prior to binding
		_magic_card._battle_system = _battle_system
		
		_battle_system.attack_plan_changed.connect(_on_plan_changed)
		_on_plan_changed(_battle_system.attack_plan)
		
	for card in [_melee_card, _ranged_card, _magic_card, _crit_card, _defense_card]:
		card.bind(player)
		
	if not Events.skill_node_hovered.is_connected(_on_skill_node_hovered):
		Events.skill_node_hovered.connect(_on_skill_node_hovered)
		Events.skill_node_unhovered.connect(_on_skill_node_unhovered)

	if board != null:
		if board.blade_size != null:
			board.blade_size.value_changed.connect(_melee_card.flash_unmute)
		if board.blade_damage != null:
			board.blade_damage.value_changed.connect(_melee_card.flash_unmute)
		if board.range != null:
			board.range.value_changed.connect(_ranged_card.flash_unmute)
		if board.spell_damage != null:
			board.spell_damage.value_changed.connect(_magic_card.flash_unmute)
		if board.armor != null:
			board.armor.value_changed.connect(_defense_card.flash_unmute)
		if board.crit_chance != null:
			board.crit_chance.value_changed.connect(_crit_card.flash_unmute)
		if board.crit_multiplier != null:
			board.crit_multiplier.value_changed.connect(_crit_card.flash_unmute)


func _on_plan_changed(plan: AttackPlan) -> void:
	var mode := plan.mode if plan != null else BattleSystem.AttackMode.NONE
	# Manage (no mode selected) un-dims every card — the design's "reference
	# state". Defense is always active/undimmed: it's not mode-bound, there's
	# no "select Defense" input channel.
	var manage := mode == BattleSystem.AttackMode.NONE
	_melee_card.set_active(manage or mode == BattleSystem.AttackMode.MELEE)
	_ranged_card.set_active(manage or mode == BattleSystem.AttackMode.RANGED)
	_magic_card.set_active(manage or mode == BattleSystem.AttackMode.MAGIC)
	_crit_card.set_active(true)
	_defense_card.set_active(true)


func _on_skill_node_hovered(node: SkillNode) -> void:
	if node == null or node.owned_by != _player:
		return
	_melee_card.set_hover_node(node)
	_ranged_card.set_hover_node(node)
	_crit_card.set_hover_node(node)
	_defense_card.set_hover_node(node)


func _on_skill_node_unhovered() -> void:
	_melee_card.set_hover_node(null)
	_ranged_card.set_hover_node(null)
	_crit_card.set_hover_node(null)
	_defense_card.set_hover_node(null)
