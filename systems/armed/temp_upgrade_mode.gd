class_name TempUpgradeMode
extends ArmedMode

## A temp-upgrade card armed on top of a [BladeMode] (#406) — only ever there:
## owner, 2026-09-30, a temp upgrade arms "Only with a blade". Its click
## toggles the upgrade onto a node; it stays armed either way. Popping the
## blade pops it too — the arm never outlives its blade.

## The armed addon scene — the kind ([method SkillNodeAddon.get_kind]).
var scene: PackedScene


func _init(p_ctl: PlayerInputController, p_scene: PackedScene) -> void:
	ctl = p_ctl
	scene = p_scene


func handle_left_click(node: SkillNode) -> bool:
	return ctl.request_temp_upgrade_at(node)


func icon() -> Texture2D:
	return SkillNodeAddon.icon_of(scene)


func icon_tint() -> Color:
	return SkillNodeAddon.tint_of(scene)
