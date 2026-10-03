class_name RangedMode
extends AttackArmMode

## Ranged armed, no target yet: a click on a valid target aims the volley and
## pushes [TargetMode]. Reload refills the quiver.


func _init(p_ctl: PlayerInputController) -> void:
	super(p_ctl, BattleSystem.AttackMode.RANGED)


const _AMMO_ROSTER: AmmoTypeRoster = preload("res://attack/ammo/ammo_type_roster.tres")


## The sensed-pickability lever (#1033) on the seat's fog: on while this
## level's plan is armed and the attacker's quiver holds scout stock — the
## scout shot's target set is the sensed nodes. VisionSystem owns the lever,
## this level owns the mode; the plan never writes another system's state.
func _on_plan_set() -> void:
	_sync_pick_sensed()


func _sync_pick_sensed() -> void:
	var vision := ctl.vision_system
	if vision == null:
		return
	var want := false
	var ranged := plan() as RangedAttackPlan
	if ranged != null:
		ranged.viewer_vision = vision
		if ranged.attacker != null and ranged.attacker.stat_board != null:
			var quiver: Quiver = ranged.attacker.stat_board.arrows
			if quiver != null:
				for t in _AMMO_ROSTER.sorted():
					if t.is_scout() and quiver.stock_of(t.id) > 0:
						want = true
						break
	vision.pick_sensed = want


func handle_left_click(node: SkillNode) -> bool:
	if plan() == null:
		return false
	if set_target(node):
		stack.push(TargetMode.new(self))
	return true


func set_target(node: SkillNode) -> bool:
	var p := plan() as RangedAttackPlan
	return p != null and p.set_target(node)


func reload() -> bool:
	ctl.request_reload()
	return true
