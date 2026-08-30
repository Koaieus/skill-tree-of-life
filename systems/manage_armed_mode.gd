class_name ManageArmedMode
extends ArmedMode

## A ManageBody tray card is armed (#338, #404) — Deallocate/Stake/Extract.
## ALLOCATE is deliberately excluded: arming it is cosmetic (cursor + card
## affordance only, per the acceptance spec — "the button is
## discoverable/tinted, the raw click is the accelerator"), and treating it
## as a poppable mode would regress right-click pin-toggle and gate the D key
## off for no functional reason the moment a player clicks the Allocate card,
## which is otherwise the idle default. Lowest priority in
## PlayerInputController._armed_modes: unlike TempUpgradeArmedMode (nests
## inside an attack plan), a Manage verb never coexists with an attack plan or
## core-move targeting (arm_manage_verb / enter_core_move_targeting enforce
## that mutual exclusion), so nesting order against those doesn't matter — it
## only needs to pop before falling through to pin-toggle / PauseMenu.

var _ctl: PlayerInputController


func _init(ctl: PlayerInputController) -> void:
	_ctl = ctl


func is_armed() -> bool:
	var v: PlayerInputController.ManageVerb = _ctl._manage_arm
	return v == PlayerInputController.ManageVerb.STAKE \
			or v == PlayerInputController.ManageVerb.EXTRACT \
			or v == PlayerInputController.ManageVerb.DEALLOCATE


func pop() -> bool:
	if not is_armed():
		return false
	_ctl._set_manage_arm(PlayerInputController.ManageVerb.NONE)
	return true


## Badge art + palette key per armed verb (#664). ALLOCATE is absent for the
## same reason it is absent from [method is_armed]: it is not an armed mode at
## all, and "no badge ⇔ the plain default allocate" is the rule that makes the
## whole channel legible. Never add an Allocate entry here.
##
## Deallocate is `lorc/cycle`, a closed loop, NOT a circle-X. **Owner call
## 2026-08-29:** deallocation is "removing points, revoking your life force (to
## be spent elsewhere), movement …, topological pivots, build pivots &
## respeccing, it's a LOT". A circle-X reads as *abort* — which would say
## "click to cancel the armed mode", the one meaning it must not have. A ring
## says the points go somewhere and come back around to be respent.
const _VERB_ICON := {
	PlayerInputController.ManageVerb.DEALLOCATE:
			preload("res://assets/icons/addons/armed_deallocate.png"),
	PlayerInputController.ManageVerb.STAKE:
			preload("res://assets/icons/addons/armed_stake.png"),
	PlayerInputController.ManageVerb.EXTRACT:
			preload("res://assets/icons/addons/armed_extract.png"),
}

## Palette key per verb — the lower-cased enum name, which is exactly what
## [method ActionPalette.color_for] takes. Stake and Extract are one piece of
## art and its vertical mirror (baked, see `assets/icons/addons/mapping.txt`),
## so the colour is the only thing telling them apart at a glance.
const _VERB_PALETTE_KEY := {
	PlayerInputController.ManageVerb.DEALLOCATE: &"deallocate",
	PlayerInputController.ManageVerb.STAKE: &"stake",
	PlayerInputController.ManageVerb.EXTRACT: &"extract",
}

const _PALETTE := preload("res://ui/theme/action_palette.tres")


func icon() -> Texture2D:
	if not is_armed():
		return null
	return _VERB_ICON.get(_ctl._manage_arm, null)


func icon_tint() -> Color:
	if not is_armed():
		return Color.TRANSPARENT
	return _PALETTE.color_for(_VERB_PALETTE_KEY.get(_ctl._manage_arm, &""))
