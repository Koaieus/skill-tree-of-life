class_name AttackPlanMode
extends ArmedMode

## INTERIM (until the attack levels land): the whole attack side as one level
## wrapping today's plan grammar. It is the sole seat-side writer of the plan
## slot — pushing requests the mode, popping cancels it, and nothing listens to
## the slot to move the stack. A push the slot refuses (mid-swing) never lands.
##
## Right-click first retreats inside the plan ([method pop_within]); only when
## the plan has nothing left to pop does the level itself pop. A landed launch
## pops the level without cancelling: the slot tears the spent plan down itself.

const _MODE_STAT_ID := {
	BattleSystem.AttackMode.MELEE: &"strength",
	BattleSystem.AttackMode.RANGED: &"dexterity",
	BattleSystem.AttackMode.MAGIC: &"intelligence",
}
const _MODE_ICON := {
	BattleSystem.AttackMode.MELEE: preload("res://assets/icons/addons/armed_melee.png"),
	BattleSystem.AttackMode.RANGED: preload("res://assets/icons/addons/armed_ranged.png"),
	BattleSystem.AttackMode.MAGIC: preload("res://assets/icons/addons/armed_magic.png"),
}
## Melee before a pivot is picked: the hilt alone, blade still to be formed (#683).
const _MELEE_HILT_ICON := preload("res://assets/icons/addons/armed_melee_hilt.png")

var mode: BattleSystem.AttackMode
var _launched := false


func _init(p_ctl: PlayerInputController, p_mode: BattleSystem.AttackMode) -> void:
	ctl = p_ctl
	mode = p_mode


## `request_attack_mode` is void and drops the request while the slot is
## locked, so the slot is read back rather than trusted.
func on_pushed() -> bool:
	var bs := ctl.battle_system
	if bs == null:
		return false
	bs.request_attack_mode(mode)
	return bs.is_attacking and bs.attack_mode == mode


func on_popped() -> void:
	var bs := ctl.battle_system
	if _launched or bs == null:
		return
	if bs.is_attacking and not bs.is_launching:
		bs.cancel_attack()


func on_command_resolved(command: Command, success: bool) -> void:
	if success and command is LaunchAttackCommand:
		_launched = true
		pop_self()


func handle_left_click(node: SkillNode) -> bool:
	var plan := ctl._active_attack_plan()
	if plan == null:
		return false
	plan.handle_left_click(node)
	return true


func pop_within() -> bool:
	var plan := ctl._active_attack_plan()
	return plan != null and plan.pop()


func reload() -> bool:
	var plan := ctl._active_attack_plan()
	if plan is RangedAttackPlan:
		ctl.request_reload()
		return true
	if plan is MeleeAttackPlan:
		ctl.reform_blade()
		return true
	return false


func tint() -> Color:
	var stat_id: StringName = _MODE_STAT_ID.get(mode, &"")
	if stat_id == &"":
		return Color.TRANSPARENT
	var def := StatRegistry.get_def(stat_id)
	return def.tint_color if def != null else Color.TRANSPARENT


func icon() -> Texture2D:
	var plan := ctl._active_attack_plan()
	if plan is MeleeAttackPlan and (plan as MeleeAttackPlan).source == null:
		return _MELEE_HILT_ICON
	if plan is MagicAttackPlan:
		var spell := (plan as MagicAttackPlan).spell
		if spell != null and spell.icon != null:
			return spell.icon
	return _MODE_ICON.get(mode, null)


func icon_tint() -> Color:
	return tint()
