@tool
class_name IdentityBadge
extends Control

static func composite(_identity: Identity, _size_px: int) -> ImageTexture:
	return null

@export var identity: Identity
@export var emissive_tier: Emissive.Tier = Emissive.Tier.LABEL
var last_draw_color := Color.TRANSPARENT

static func clear_cache() -> void:
	pass
