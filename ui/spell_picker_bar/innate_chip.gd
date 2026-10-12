@tool
class_name InnateChip
extends HBoxContainer

## One innate entry of a spell tile's affinity row: the aspect's small
## [IdentityBadge] plus the innate point count. [method bind] resolves the
## aspect through [IdentityRoster]; an unknown id shows the count alone.

## Edge length of the aspect badge, in pixels.
@export_range(8, 48) var badge_px: int = 16:
	set(value):
		badge_px = value
		if _badge != null:
			_badge.size_px = value

@onready var _badge: IdentityBadge = %Badge
@onready var _count: Label = %Count


func _ready() -> void:
	_badge.size_px = badge_px


func bind(aspect_id: StringName, count: int) -> void:
	pass
