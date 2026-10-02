@abstract
class_name AttackArmMode
extends ArmedMode

## The base of the three attack levels — [MeleeMode], [RangedMode],
## [MagicMode]. The level OWNS the plan: pushing creates it (or adopts one of
## this mode the slot already holds for this player), popping drops it, and
## [method ArmedStack.attack_plan] exposes it. A push mid-swing
## ([member BattleSystem.is_launching]) is refused.
##
## The level publishes its plan into [member BattleSystem.attack_plan], so the
## forwarders resolve to the same object — one plan, two doors — and follows
## that door when something else writes it (a cancel, a launch's release, a
## sandbox arming directly): it keeps the slot's plan when it is this mode and
## this player's, and drops to null otherwise.
##
## The plan owns *which node*; the step levels above this one ([BladeMode],
## [TargetMode]) own *what the next click means*. Levels move on events, never
## by watching the plan: after this player's launch
## ([signal BattleSystem.attack_launched]) the slot's release
## ([signal BattleSystem.attack_plan_changed] with null) creates a fresh plan,
## so the arm stays up with an empty one. A cancel-driven release does not
## re-arm — only a launch sets the flag.

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

var mode: BattleSystem.AttackMode
var _launched := false
var _plan: AttackPlan = null


func _init(p_ctl: PlayerInputController, p_mode: BattleSystem.AttackMode) -> void:
	ctl = p_ctl
	mode = p_mode


## This level's plan, or null once dropped.
func plan() -> AttackPlan:
	return _plan


func on_pushed() -> bool:
	if not _request():
		return false
	var bs := ctl.battle_system
	bs.attack_launched.connect(_on_attack_launched)
	bs.attack_plan_changed.connect(_on_attack_plan_changed)
	bs.plan_reset.connect(_on_slot_reset)
	return true


func on_popped() -> void:
	var bs := ctl.battle_system
	if bs == null:
		return
	if bs.attack_launched.is_connected(_on_attack_launched):
		bs.attack_launched.disconnect(_on_attack_launched)
	if bs.attack_plan_changed.is_connected(_on_attack_plan_changed):
		bs.attack_plan_changed.disconnect(_on_attack_plan_changed)
	if bs.plan_reset.is_connected(_on_slot_reset):
		bs.plan_reset.disconnect(_on_slot_reset)
	_launched = false
	if _plan != null and bs.attack_plan == _plan and not bs.is_launching:
		bs.cancel_attack()
	_set_plan(null)


## Clear this level's plan selection and announce [signal ArmedStack.plan_reset].
## Refused with no plan or mid-swing ([member BattleSystem.is_launching]).
func reset_plan() -> void:
	if _plan == null or ctl.battle_system == null or ctl.battle_system.is_launching:
		return
	_plan.reset()
	if stack != null:
		stack.plan_reset.emit()


## The slot's RESET door ([method BattleSystem.reset_plan]) relayed onto the
## stack. Goes with the slot.
func _on_slot_reset() -> void:
	if stack != null:
		stack.plan_reset.emit()


## Aim at [param node] — the ranged and magic arms' verb, which a
## [TargetMode] above them reuses to retarget. False = nothing changed.
func set_target(_node: SkillNode) -> bool:
	return false


## Create this level's plan — or adopt the slot's when it already is this
## mode's and this player's (a repeat arm keeps its plan) — and publish it to
## [member BattleSystem.attack_plan]. False mid-swing or when none can be made.
func _request() -> bool:
	var bs := ctl.battle_system if ctl != null else null
	if bs == null or bs.is_launching:
		return false
	var p := _ours(bs.attack_plan)
	if p == null:
		p = bs._new_plan(_plan_class())
		if p == null:
			return false
		bs.attack_plan = p
	_set_plan(_ours(p))
	return true


func _plan_class() -> Script:
	match mode:
		BattleSystem.AttackMode.MELEE: return MeleeAttackPlan
		BattleSystem.AttackMode.RANGED: return RangedAttackPlan
		_: return MagicAttackPlan


func _ours(p: AttackPlan) -> AttackPlan:
	if p != null and p.mode == mode and p.attacker == ctl.player:
		return p
	return null


func _set_plan(p: AttackPlan) -> void:
	if _plan == p:
		return
	_plan = p
	if stack != null:
		stack.sync_attack_plan()


func _on_attack_launched(_mode: BattleSystem.AttackMode, _spell: SpellDef) -> void:
	var flying := ctl.battle_system.in_flight_plan
	if flying != null and flying.attacker == ctl.player and flying.mode == mode:
		_launched = true


## Deferred: re-requesting inside the slot's own `attack_plan_changed(null)`
## emission would hand listeners still queued behind this one a stale null.
func _on_attack_plan_changed(p: AttackPlan) -> void:
	_set_plan(_ours(p))
	if p == null and _launched:
		_launched = false
		_rearm.call_deferred()


func _rearm() -> void:
	if stack == null or not stack.has(self):
		return
	if not _request():
		pop_self()


func tint() -> Color:
	var stat_id: StringName = _MODE_STAT_ID.get(mode, &"")
	if stat_id == &"":
		return Color.TRANSPARENT
	var def := StatRegistry.get_def(stat_id)
	return def.tint_color if def != null else Color.TRANSPARENT


func icon() -> Texture2D:
	return _MODE_ICON.get(mode, null)


func icon_tint() -> Color:
	return tint()
