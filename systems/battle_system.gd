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

func request_attack_mode(mode: AttackMode) -> void:
	if attack_mode == mode:
		return
	match mode:
		AttackMode.NONE:    cancel_attack()
		AttackMode.MELEE:   attack_plan = _new_plan(MeleeAttackPlan)
		AttackMode.RANGED:  attack_plan = _new_plan(RangedAttackPlan)
		AttackMode.MAGIC:   attack_plan = _new_plan(MagicAttackPlan)

func _new_plan(plan_class: Script) -> AttackPlan:
	var p: AttackPlan = plan_class.new()
	p.attacker = turn_manager.current_entity
	return p

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.
