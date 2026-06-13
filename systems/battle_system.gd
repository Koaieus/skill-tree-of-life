class_name BattleSystem
extends Node

enum AttackMode {
	NONE,
	MELEE,
	RANGED,
	MAGIC
}

signal attack_plan_changed(plan: AttackPlan)

@export var turn_manager: TurnManager


var attack_plan: AttackPlan:
	set(value):
		if attack_plan != value:
			attack_plan = value
			print('Attack plan is now: %s [%s]' % [value, attack_mode])
			attack_plan_changed.emit(value)

var attack_mode: AttackMode:
	get(): return attack_plan.mode if attack_plan else AttackMode.NONE

var is_attacking: bool:
	get(): return attack_plan != null

func cancel_attack() -> void:
	if is_attacking:
		_reset()
	else:
		push_warning('Cannot cancel attack: not attacking')

func _reset() -> void:
	if attack_plan:
		attack_plan = null


func _on_attack_mode_requested(mode: AttackMode) -> void:
	if is_attacking and attack_plan.mode == mode:
		push_warning('Already in mode %s' % mode)
		
	match mode:
		AttackMode.NONE:
			cancel_attack()
		AttackMode.MELEE:
			var new_plan: MeleeAttackPlan = MeleeAttackPlan.new()
			new_plan.attacker = turn_manager.current_entity
			attack_plan = new_plan
		AttackMode.RANGED:
			var new_plan: RangedAttackPlan = RangedAttackPlan.new()
			new_plan.attacker = turn_manager.current_entity
			attack_plan = new_plan
		AttackMode.MAGIC:
			var new_plan: MagicAttackPlan = MagicAttackPlan.new()
			new_plan.attacker = turn_manager.current_entity
			attack_plan = new_plan
		
	

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.
