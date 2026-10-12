@tool
class_name InfusionSockets
extends Control


func bind(_plan: MagicAttackPlan, _stack: ArmedStack = null) -> void:
	pass


func socket_count() -> int:
	return -1


func ghost_text() -> String:
	return "stub"


func socket(_i: int) -> InfusionSocket:
	return null


func wheel() -> AspectWheel:
	return null
