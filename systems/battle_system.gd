class_name BattleSystem
extends Node

enum AttackMode {
	NONE,
	MELEE,
	RANGED,
	MAGIC
}

signal attack_plan_changed(plan: AttackPlan)
## Fires for both plan swap and plan-internal mutation. Subscribers that
## care about lifecycle (mount per-mode UI) use [signal attack_plan_changed];
## subscribers that care about content (re-paint highlights) use this one.
signal attack_plan_state_changed

@export var turn_manager: TurnManager


var attack_plan: AttackPlan:
	set(value):
		if attack_plan == value:
			return
		if attack_plan != null and attack_plan.state_changed.is_connected(_on_plan_state_changed):
			attack_plan.state_changed.disconnect(_on_plan_state_changed)
		attack_plan = value
		if attack_plan != null:
			attack_plan.state_changed.connect(_on_plan_state_changed)
		print('Attack plan is now: %s' % value)
		attack_plan_changed.emit(value)
		attack_plan_state_changed.emit()


func _on_plan_state_changed() -> void:
	attack_plan_state_changed.emit()

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
