@tool
class_name PriceBadge
extends HBoxContainer
## One currency on a shop card's price strip: a glyph and a count ("[blade] 2").
##
## A pure view — it is told its [member icon], [member tint] and [member count]
## and knows nothing about stats, aspects or affordability. The host
## ([TempUpgradeButton]) resolves a cost's stat id to its glyph and hue.

## The currency glyph. Null hides the glyph, leaving the bare count.
@export var icon: Texture2D = null:
	set(v):
		icon = v
		if is_node_ready():
			_repaint()

## The currency hue, unlifted — painted on the glyph and the count alike.
@export var tint: Color = Color.WHITE:
	set(v):
		tint = v
		if is_node_ready():
			_repaint()

## How many of the currency the card costs.
@export var count: int = 1:
	set(v):
		count = v
		if is_node_ready():
			_repaint()

@onready var _icon: TextureRect = %Icon
@onready var _count: Label = %Count


func _ready() -> void:
	_repaint()


## The count as printed, e.g. "2" — what a reader of the strip sees.
func count_text() -> String:
	return _count.text if _count != null else str(count)


func _repaint() -> void:
	_icon.texture = icon
	_icon.visible = icon != null
	_icon.modulate = tint
	_count.text = str(count)
	_count.modulate = tint
