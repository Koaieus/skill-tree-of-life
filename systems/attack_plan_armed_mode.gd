class_name AttackPlanArmedMode
extends ArmedMode

## An attack plan (melee/ranged/magic) is armed for this player (#404,
## generalized #406). Wraps the existing "pop the plan's own stack, or
## cancel the plan entirely if it has nothing left to pop" logic.

## Which attribute's identity colour each attack mode borrows for the #412
## viewport glow. Per `.claude/rules/ui-palette.md`, `StatDef.tint_color` is the
## single source of truth for these — this maps to the id, never to a literal
## `Color`. (`ui/announcement_layer/callout_band.gd` still hardcodes the same
## three values; refitting it onto this read is deliberately out of scope.)
const _MODE_STAT_ID := {
	BattleSystem.AttackMode.MELEE: &"strength",
	BattleSystem.AttackMode.RANGED: &"dexterity",
	BattleSystem.AttackMode.MAGIC: &"intelligence",
}

var _ctl: PlayerInputController


func _init(ctl: PlayerInputController) -> void:
	_ctl = ctl


func is_armed() -> bool:
	return _ctl.can_player_act() and _ctl._active_attack_plan() != null


func pop() -> bool:
	var plan := _ctl._active_attack_plan()
	if plan == null:
		return false
	if not plan.pop():
		_ctl.battle_system.cancel_attack()
	return true


## The armed mode's identity colour, lifted to the bloom tier (#412).
##
## `Emissive.tint`, not `Emissive.at` — the three modes must read as *equally*
## loud, and `emissive.gd` records the empirical finding this is made of: bloom
## thresholds per channel and Rec.709 discounts blue ~10x against green, so
## INT-blue at the same nominal stop as STR-red visibly under-blooms. `tint`
## normalises the hue's own luminance out first.
func tint() -> Color:
	if not is_armed():
		return Color.TRANSPARENT
	var stat_id: StringName = _MODE_STAT_ID.get(_ctl.battle_system.attack_mode, &"")
	if stat_id == &"":
		return Color.TRANSPARENT
	var def := StatRegistry.get_def(stat_id)
	if def == null:
		return Color.TRANSPARENT
	return Emissive.tint(def.tint_color, Emissive.ALERT)
