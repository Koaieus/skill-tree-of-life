class_name TempUpgradeMode
extends ArmedMode

## A temp-upgrade card armed on top of the melee [AttackPlanMode] (#406). Its
## click toggles the upgrade onto a node; it stays armed either way. Popping
## the attack level pops it too — the arm never outlives its plan.

const _PALETTE := preload("res://ui/theme/action_palette.tres")
## One icon per addon scene; instancing the scene is the only way to read it.
static var _icon_cache: Dictionary = {}

var def: TempUpgradeDef


func _init(p_ctl: PlayerInputController, p_def: TempUpgradeDef) -> void:
	ctl = p_ctl
	def = p_def


func handle_left_click(node: SkillNode) -> bool:
	return ctl.request_temp_upgrade_at(node)


func icon() -> Texture2D:
	var scene: PackedScene = def.scene
	if scene == null:
		return null
	if not _icon_cache.has(scene):
		var tmp := scene.instantiate()
		_icon_cache[scene] = (tmp as SkillNodeAddon).icon
		tmp.free()
	return _icon_cache[scene]


func icon_tint() -> Color:
	return _PALETTE.color_for(def.id)
