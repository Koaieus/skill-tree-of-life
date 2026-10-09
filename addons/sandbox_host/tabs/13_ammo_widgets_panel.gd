@tool
extends PanelContainer

## Live tab panel for the ranged card's widgets: one stock slider drives a
## [SheafPile] sitting behind a [SendBar]; the bar's requests set its own value
## here, as the card will. Under a bloom viewport so the border glow reads.

@onready var _stock: HSlider = %Stock
@onready var _tint: ColorPickerButton = %Tint
@onready var _readout: Label = %Readout
@onready var _pile: SheafPile = %Pile
@onready var _bar: SendBar = %Bar


func noop(_obj: Object) -> void:
	pass


func _ready() -> void:
	_stock.value_changed.connect(_on_stock)
	_tint.color_changed.connect(_on_tint)
	_bar.value_requested.connect(_on_requested)
	_on_tint(_tint.color)
	_on_stock(_stock.value)


func _on_stock(v: float) -> void:
	var n := int(v)
	_pile.count = n
	_bar.stock = n
	_bar.value = mini(_bar.value, n)
	_show()


func _on_tint(c: Color) -> void:
	_pile.tint = c
	_bar.tint = c


func _on_requested(n: int) -> void:
	_bar.value = n
	_show()


func _show() -> void:
	_readout.text = "send %d / %d  ·  lit %d" % [_bar.value, _bar.stock, SendBar.lit_thirds(_bar.stock, _bar.border_decades)]
