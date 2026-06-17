extends Node2D

@onready var skill_blade: SkillBlade = $SkillBlade

func _on_swing_pressed() -> void:
	skill_blade.swing()
