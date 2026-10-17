@tool
class_name IdentityChip
extends PanelContainer

## An `[identity × count]` readout as a dark pill: the authored [StyleBoxFlat]
## panel's border, the bare [method IdentityBadge.glyph] and the count all take
## the identity's tint lifted through [method Emissive.at] at
## [member emissive_tier]. The pill border is the only frame (no
## [IdentityBadge] child). The caller passes the [Identity]; the chip owns no
## lookup. A null identity shows the count alone in [member neutral_color].
##
## The scene's stylebox is shared by every instance, so the chip duplicates it
## once on first refresh and writes only its own copy.

## The identity shown; null shows the count alone, neutral.
@export var identity: Identity:
	set(value):
		identity = value
		_refresh()
## How lit the border, glyph and count read; the identity stores its hue unlifted.
@export var emissive_tier: Emissive.Tier = Emissive.Tier.LABEL:
	set(value):
		emissive_tier = value
		_refresh()
## Edge length of the bare glyph, in pixels.
@export_range(8, 48) var glyph_px: int = 20:
	set(value):
		glyph_px = value
		_refresh()
## The pill's dark fill — the contrast that keeps a tint legible on a light tile.
@export var fill_color := Color(0.09, 0.09, 0.12, 0.85):
	set(value):
		fill_color = value
		_refresh()
## Border and count colour when no identity is bound.
@export var neutral_color := Color(0.75, 0.75, 0.8, 1.0):
	set(value):
		neutral_color = value
		_refresh()

## This instance's own copy of the authored panel stylebox.
var _style: StyleBoxFlat

@onready var _glyph: TextureRect = %Glyph
@onready var _count: Label = %Count


func _ready() -> void:
	_refresh()


## Show `of`'s glyph and `count`, both in its lit tint.
func bind(of: Identity, count: int) -> void:
	identity = of
	if is_node_ready():
		_count.text = str(count)


func _refresh() -> void:
	if not is_node_ready():
		return
	if _style == null:
		var authored := get_theme_stylebox(&"panel") as StyleBoxFlat
		_style = authored.duplicate() if authored != null else StyleBoxFlat.new()
		add_theme_stylebox_override(&"panel", _style)
	var color := Emissive.at(identity.tint, Emissive.stops(emissive_tier)) if identity != null else neutral_color
	_style.bg_color = fill_color
	_style.border_color = color
	_glyph.texture = IdentityBadge.glyph(identity, glyph_px)
	_glyph.custom_minimum_size = Vector2(glyph_px, glyph_px)
	_glyph.visible = identity != null
	_glyph.self_modulate = color
	_count.add_theme_color_override(&"font_color", color)
