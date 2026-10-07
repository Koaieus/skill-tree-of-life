@tool
class_name InfusionRow
extends HBoxContainer


func bind(_plan: MagicAttackPlan) -> void:
	pass


func stepper_ids() -> Array[StringName]:
	return []


func value_text(_id: StringName) -> String:
	return ""


func plus_button(_id: StringName) -> Button:
	return null


func minus_button(_id: StringName) -> Button:
	return null


func header_text() -> String:
	return ""
