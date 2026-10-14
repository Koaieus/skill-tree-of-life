@tool
class_name RiderBlastLayer
extends Node2D

@export var emissive_tier: Emissive.Tier = Emissive.Tier.VALUE
var rider: Identity = null
var layer: int = 0
var radius: float = 0.0


func color() -> Color:
	return Color.BLACK
