class_name BladeNodeMenuMode
extends ArmedMode

## Stub (red commit).

var blade: BladeMode
var node: SkillNode


func _init(p_blade: BladeMode, p_node: SkillNode) -> void:
	blade = p_blade
	ctl = p_blade.ctl
	node = p_node


func unpick() -> void:
	pass


func pick(_scene: PackedScene) -> void:
	pass
