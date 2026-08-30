class_name TempUpgradeArmedMode
extends ArmedMode

## Innermost armed-mode level (#406): a temp-upgrade card is armed, waiting
## for a click on a blade member to resolve. Sits ON TOP OF an already-armed
## attack plan, so it must pop before the plan does — checked first in
## PlayerInputController._armed_modes.

var _ctl: PlayerInputController


func _init(ctl: PlayerInputController) -> void:
	_ctl = ctl


func is_armed() -> bool:
	return _ctl._temp_upgrade_arm != null


func pop() -> bool:
	if _ctl._temp_upgrade_arm == null:
		return false
	_ctl._set_temp_upgrade_arm(null)
	return true


const _PALETTE := preload("res://ui/theme/action_palette.tres")

## Lazy per-scene icon cache, mirroring [member MeleeAttackPlan._cost_cache]:
## instantiate once off the tree, read the authored [member
## SkillNodeAddon.icon], free, cache. The addon scene is the source of truth
## for its own art (#664) — the badge must show the SAME glyph the tray card
## the player just pressed showed, and duplicating the texture reference here
## is how those two drift apart. Never instantiate per call: `icon()` is read
## on every armed-state refresh.
static var _icon_cache: Dictionary = {}


func icon() -> Texture2D:
	if not is_armed():
		return null
	var scene: PackedScene = _ctl._temp_upgrade_arm.get("scene", null)
	if scene == null:
		return null
	if not _icon_cache.has(scene):
		var tmp := scene.instantiate()
		_icon_cache[scene] = (tmp as SkillNodeAddon).icon
		tmp.free()
	return _icon_cache[scene]


## Keyed by the catalog entry's `id`, which [ActionPalette] uses verbatim —
## so a future third temp upgrade needs a palette entry and nothing else here.
func icon_tint() -> Color:
	if not is_armed():
		return Color.TRANSPARENT
	return _PALETTE.color_for(_ctl._temp_upgrade_arm.get("id", &""))
