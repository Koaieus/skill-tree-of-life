@abstract
class_name AttackArmMode
extends ArmedMode

## The base of the three attack levels — [MeleeMode], [RangedMode],
## [MagicMode] — each the sole seat-side writer of the plan slot while it
## stands: pushing requests its mode, popping cancels it. A push the slot
## refuses (mid-swing) never lands.
##
## The plan owns *which node*; the step levels above this one ([BladeMode],
## [TargetMode]) own *what the next click means*. Levels move on events, never
## by watching the plan: after this player's launch
## ([signal BattleSystem.attack_launched]) the slot's release
## ([signal BattleSystem.attack_plan_changed] with null) re-requests the mode,
## so the arm stays up with a fresh, empty plan. A cancel-driven release does
## not re-arm — only a launch sets the flag.

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


func _init(p_ctl: PlayerInputController, p_mode: BattleSystem.AttackMode) -> void:
	ctl = p_ctl
	mode = p_mode


## This level's live plan: the slot's, when it is this player's and this mode's.
func plan() -> AttackPlan:
	var p := ctl._active_attack_plan() if ctl != null else null
	return p if p != null and p.mode == mode else null


## `request_attack_mode` is void and drops the request while the slot is
## locked, so the slot is read back rather than trusted.
func on_pushed() -> bool:
	if not _request():
		return false
	var bs := ctl.battle_system
	bs.attack_launched.connect(_on_attack_launched)
	bs.attack_plan_changed.connect(_on_attack_plan_changed)
	return true


func on_popped() -> void:
	var bs := ctl.battle_system
	if bs == null:
		return
	if bs.attack_launched.is_connected(_on_attack_launched):
		bs.attack_launched.disconnect(_on_attack_launched)
	if bs.attack_plan_changed.is_connected(_on_attack_plan_changed):
		bs.attack_plan_changed.disconnect(_on_attack_plan_changed)
	_launched = false
	if bs.is_attacking and bs.attack_mode == mode and not bs.is_launching:
		bs.cancel_attack()


## Aim at [param node] — the ranged and magic arms' verb, which a
## [TargetMode] above them reuses to retarget. False = nothing changed.
func set_target(_node: SkillNode) -> bool:
	return false


func _request() -> bool:
	var bs := ctl.battle_system if ctl != null else null
	if bs == null:
		return false
	bs.request_attack_mode(mode)
	return bs.is_attacking and bs.attack_mode == mode


func _on_attack_launched(_mode: BattleSystem.AttackMode, _spell: SpellDef) -> void:
	var flying := ctl.battle_system.in_flight_plan
	if flying != null and flying.attacker == ctl.player and flying.mode == mode:
		_launched = true


## Deferred: re-requesting inside the slot's own `attack_plan_changed(null)`
## emission would hand listeners still queued behind this one a stale null.
func _on_attack_plan_changed(p: AttackPlan) -> void:
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
