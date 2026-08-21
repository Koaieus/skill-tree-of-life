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
## `Emissive.tint_peak`, NOT `Emissive.tint`. Both equalize loudness across
## hues; they differ in what they do to the *off-hue* channels, and for a large
## additive area that difference is the whole ballgame.
##
## `tint` normalises by Rec.709 luminance, and STR-red's luminance is only
## 0.233 — so it scales every channel by ~17x and red at ALERT comes out
## linear `(15.13, 1.01, 0.84)`. Green and blue at ~1.0 are full display white
## *on their own*, before this is even added to the background: the glow reads
## as a white frame with a red bloom halo. **Owner call 2026-08-21, testing the
## melee glow at `band_px = 140`:** "WAY TOO MUCH WHITE".
##
## `tint_peak` normalises by the peak channel instead, so the dominant channel
## lands on the tier and the rest stay proportional — red at ALERT is
## `(4.0, 0.27, 0.22)`, a 4x cut to the off-hue channels, and it reads red.
## This is the live comparison `emissive.gd` asked for before adopting it.
##
## The fix is only as good as the base hue is saturated: DEX-green and INT-blue
## carry more off-hue channel to begin with (off-hue max ~1.2 vs red's 0.27),
## so they whiten more than melee does even under `tint_peak`.
func tint() -> Color:
	if not is_armed():
		return Color.TRANSPARENT
	var stat_id: StringName = _MODE_STAT_ID.get(_ctl.battle_system.attack_mode, &"")
	if stat_id == &"":
		return Color.TRANSPARENT
	var def := StatRegistry.get_def(stat_id)
	if def == null:
		return Color.TRANSPARENT
	return Emissive.tint_peak(def.tint_color, Emissive.ALERT)
