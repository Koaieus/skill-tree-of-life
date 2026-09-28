@tool
class_name AttackPlanSlot
extends Node

signal attack_plan_changed(plan: AttackPlan)
signal attack_plan_state_changed
signal selected_spell_changed(spell: SpellDef)

@export var turn_manager: TurnManager
@export var allocation_system: AllocationSystem
@export var temp_upgrade_catalog: TempUpgradeCatalog
@export var vision_system: VisionSystem

var locked: bool = false
var attack_plan: AttackPlan
var attack_mode: BattleSystem.AttackMode = BattleSystem.AttackMode.NONE
var is_attacking: bool = false
var selected_spell: SpellDef = null
var next_melee_cw: bool = false

func request_attack_mode(_mode: BattleSystem.AttackMode) -> void: pass
func cancel_attack() -> void: pass
func reset_plan() -> void: pass
func toggle_temp_upgrade_on(_n: SkillNode, _d: TempUpgradeDef) -> bool: return false
func can_toggle_temp_upgrade_on(_n: SkillNode, _d: TempUpgradeDef) -> bool: return false
func temp_upgrade_by_id(_id: StringName) -> TempUpgradeDef: return null
func temp_upgrade_kinds() -> Array[TempUpgradeDef]: return []
