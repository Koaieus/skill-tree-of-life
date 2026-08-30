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


## The armed mode's identity colour, at its authored `StatDef` value.
##
## **Returned UNLIFTED — no `Emissive` call here.** How loud the glow burns is a
## presentation decision and belongs to the thing doing the presenting, so
## [ArmedModeGlow] owns the tier (and the `glow_stops` slider the owner tunes
## it with). This side answers only "which hue", which is the part that is
## actually a rule of the game.
func tint() -> Color:
	if not is_armed():
		return Color.TRANSPARENT
	var stat_id: StringName = _MODE_STAT_ID.get(_ctl.battle_system.attack_mode, &"")
	if stat_id == &"":
		return Color.TRANSPARENT
	var def := StatRegistry.get_def(stat_id)
	if def == null:
		return Color.TRANSPARENT
	return def.tint_color


## Badge art per attack mode (#664). Three diagonally-pointing weapons —
## **owner call 2026-08-29:** "having the basic 3 attack modes all be a
## diagonally pointing weapon is actually neat right? broadsword, bow×arrow,
## wand". The shared silhouette says *these are the same kind of thing*; the
## STR/DEX/INT tint from [method tint] carries the difference. The
## broadsword/wand similarity is that family resemblance, not a mistake.
const _MODE_ICON := {
	BattleSystem.AttackMode.MELEE: preload("res://assets/icons/addons/armed_melee.png"),
	BattleSystem.AttackMode.RANGED: preload("res://assets/icons/addons/armed_ranged.png"),
	BattleSystem.AttackMode.MAGIC: preload("res://assets/icons/addons/armed_magic.png"),
}


func icon() -> Texture2D:
	if not is_armed():
		return null
	return _MODE_ICON.get(_ctl.battle_system.attack_mode, null)


## The same attribute colour the border glow uses — reusing [method tint]
## rather than restating the three colours, so the badge and the outline can
## never drift apart.
func icon_tint() -> Color:
	return tint()
