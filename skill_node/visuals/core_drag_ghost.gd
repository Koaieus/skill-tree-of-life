class_name CoreDragGhost
extends Node2D

## The core-move drag ghost: a standalone [CorePresence] (the same scene the
## live in-node core wears) plus the hop/MP badge. The root stays at the
## parent's origin; the presence snaps to a landing or trails the cursor, and
## the badge always trails the cursor. The sigil bloom joins the presence only
## while snapped to a valid landing.

const ZLayers = preload("res://ui/z_layers.gd")

## Presence alpha while snapped to a valid landing.
@export_range(0.0, 1.0) var snapped_alpha: float = 0.85
## Presence alpha while trailing the cursor with no landing in reach.
@export_range(0.0, 1.0) var free_alpha: float = 0.4
## Badge offset from the cursor, in world units.
@export var badge_offset: Vector2 = Vector2(18, -10)

@onready var _presence: CorePresence = %Presence
@onready var _bloom: Node2D = %Presence.get_node(^"CoreSigilBloom")
@onready var _badge: Label = %Badge


func _ready() -> void:
	z_index = ZLayers.CORE_MOVE


## Dresses the presence as [param entity]'s core at [param radius]. Call once,
## after the ghost is in the tree. A null entity is a plain white core.
func configure(entity: Entity, radius: float) -> void:
	_presence.entity_tint = entity.color if entity != null else Color.WHITE
	_presence.configure(radius)
	var sigil: Sigil = null
	if entity != null and entity.core_class != null:
		_presence.set_look(entity.core_class.core_look)
		sigil = entity.core_class.sigil
	_bloom.sigil = sigil
	_bloom.visible = false


## Puts the presence at [param world]: snapped to a landing (bloom shown,
## [member snapped_alpha]) or trailing the cursor ([member free_alpha]).
func place(world: Vector2, snapped: bool) -> void:
	_presence.global_position = world
	_presence.modulate.a = snapped_alpha if snapped else free_alpha
	_bloom.visible = snapped


## Badge [param text], drawn at [param cursor] + [member badge_offset].
func set_badge(text: String, cursor: Vector2) -> void:
	_badge.text = text
	_badge.global_position = cursor + badge_offset
