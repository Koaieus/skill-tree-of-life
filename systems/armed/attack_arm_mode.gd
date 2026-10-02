@abstract
class_name AttackArmMode
extends ArmedMode

## The base of the three attack levels — [MeleeMode], [RangedMode],
## [MagicMode]. The level OWNS the plan: pushing mints it (with the seat's
## sticky preferences off [ArmedStack]), popping drops it, and
## [method ArmedStack.attack_plan] exposes it. [BattleSystem] never holds it:
## it only resolves the plan [method BattleSystem.launch_attack] is handed.
## A push mid-swing ([member BattleSystem.is_launching]) is refused, and so is
## a reset.
##
## The plan owns *which node*; the step levels above this one ([BladeMode],
## [TargetMode]) own *what the next click means*. Levels move on events, never
## by watching the plan: when THIS level's plan was the one launched
## ([signal BattleSystem.attack_launched]), its release
## ([signal BattleSystem.in_flight_plan_changed] with null) mints a fresh plan,
## so the arm stays up with an empty one. An AI's or a mirror's launch never
## touches it.

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
	bs.in_flight_plan_changed.connect(_on_in_flight_plan_changed)
	return true


func on_popped() -> void:
	var bs := ctl.battle_system
	if bs != null:
		if bs.attack_launched.is_connected(_on_attack_launched):
			bs.attack_launched.disconnect(_on_attack_launched)
		if bs.in_flight_plan_changed.is_connected(_on_in_flight_plan_changed):
			bs.in_flight_plan_changed.disconnect(_on_in_flight_plan_changed)
	_launched = false
	# The single teardown of a dropped plan: reset() frees its temp-upgrade
	# addons. A plan mid-swing is BattleSystem's to release, never ours.
	if _plan != null and (bs == null or bs.in_flight_plan != _plan):
		_plan.reset()
	_set_plan(null)


## Clear this level's plan selection and announce [signal ArmedStack.plan_reset].
## Refused with no plan or mid-swing ([member BattleSystem.is_launching]).
func reset_plan() -> void:
	if _plan == null or ctl.battle_system == null or ctl.battle_system.is_launching:
		return
	_plan.reset()
	if stack != null:
		stack.plan_reset.emit()


## Aim at [param node] — the ranged and magic arms' verb, which a
## [TargetMode] above them reuses to retarget. False = nothing changed.
func set_target(_node: SkillNode) -> bool:
	return false


## Mint this level's plan for [member PlayerInputController.player], layered
## with the seat's sticky preferences ([member ArmedStack.selected_spell],
## [member ArmedStack.next_melee_cw]). False mid-swing or when none can be made.
func _request() -> bool:
	var bs := ctl.battle_system if ctl != null else null
	if bs == null or bs.is_launching or ctl.player == null:
		return false
	# Another entity's turn: the level stands, holding no plan.
	if ctl.turn_manager != null and ctl.turn_manager.current_entity != ctl.player:
		_set_plan(null)
		return true
	var p := BattleSystem.mint_plan(mode, ctl.player, ctl.vision_system)
	if p == null:
		return false
	var seat := stack if stack != null else ctl.armed_stack
	if seat != null:
		if p is MagicAttackPlan and seat.selected_spell != null:
			(p as MagicAttackPlan).spell = seat.selected_spell
		if p is MeleeAttackPlan:
			(p as MeleeAttackPlan).swing_cw = seat.next_melee_cw
	_set_plan(p)
	return true


func _set_plan(p: AttackPlan) -> void:
	if _plan == p:
		return
	_plan = p
	_on_plan_set()
	if stack != null:
		stack.sync_attack_plan()


## Hook: this level's plan just moved (minted, dropped, swapped on re-arm).
func _on_plan_set() -> void:
	pass


func _on_attack_launched(_mode: BattleSystem.AttackMode, _spell: SpellDef) -> void:
	if _plan != null and ctl.battle_system.in_flight_plan == _plan:
		_launched = true


## Deferred: re-minting inside the release's own emission would hand listeners
## still queued behind this one a plan that appeared mid-teardown.
func _on_in_flight_plan_changed(p: AttackPlan) -> void:
	if p != null or not _launched:
		return
	_launched = false
	_set_plan(null)
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
