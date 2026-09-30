@abstract
class_name AttackStepMode
extends ArmedMode

## A step inside an attack — [BladeMode] over [MeleeMode], [TargetMode] over
## [RangedMode] / [MagicMode] — holding a typed reference to the attack level
## it refines. Its pop undoes the step on the plan ([method _undo]); it also
## pops on the events that end the step outside input: this player's launch
## ([signal BattleSystem.attack_launched] — the launch's own teardown clears
## the plan, so [method _undo] is skipped while launching) and the RESET
## button ([signal BattleSystem.plan_reset]).

var parent: AttackArmMode


func _init(p_parent: AttackArmMode) -> void:
	parent = p_parent
	ctl = p_parent.ctl


func on_pushed() -> bool:
	var bs := ctl.battle_system
	bs.attack_launched.connect(_on_attack_launched)
	bs.plan_reset.connect(_on_plan_reset)
	return true


func on_popped() -> void:
	var bs := ctl.battle_system
	if bs.attack_launched.is_connected(_on_attack_launched):
		bs.attack_launched.disconnect(_on_attack_launched)
	if bs.plan_reset.is_connected(_on_plan_reset):
		bs.plan_reset.disconnect(_on_plan_reset)
	if bs.is_launching:
		return
	var p := parent.plan()
	if p != null:
		_undo(p)


## Clear this step's writes on [param p].
@abstract func _undo(p: AttackPlan) -> void


func _on_attack_launched(_mode: BattleSystem.AttackMode, _spell: SpellDef) -> void:
	var flying := ctl.battle_system.in_flight_plan
	if flying != null and flying.attacker == ctl.player:
		pop_self()


func _on_plan_reset() -> void:
	pop_self()
