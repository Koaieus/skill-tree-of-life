@tool
extends PanelContainer

## Live tab panel for the ranged card's widgets: one stock slider drives a
## [SheafPile] sitting behind a [SendBar]; the bar's requests set its own value
## here, as the card will. Under a bloom viewport so the border glow reads.
## Below them a [ReorderRow] of one [AmmoCard] per roster type: drag to eye
## the reorder motion, with its settle / lift knobs and a default-order button.

const _CARD_SCENE := preload("res://ui/hud/command_tray/bodies/ammo_card.tscn")
const _ROSTER: AmmoTypeRoster = preload("res://attack/ammo/ammo_type_roster.tres")

@onready var _stock: HSlider = %Stock
@onready var _tint: ColorPickerButton = %Tint
@onready var _readout: Label = %Readout
@onready var _pile: SheafPile = %Pile
@onready var _bar: SendBar = %Bar
@onready var _row: ReorderRow = %Row
@onready var _settle: HSlider = %Settle
@onready var _lift: HSlider = %Lift
@onready var _default_order: Button = %DefaultOrder
@onready var _order_readout: Label = %OrderReadout


func noop(_obj: Object) -> void:
	pass


func _ready() -> void:
	_stock.value_changed.connect(_on_stock)
	_tint.color_changed.connect(_on_tint)
	_bar.value_requested.connect(_on_requested)
	_on_tint(_tint.color)
	_on_stock(_stock.value)
	for t in _ROSTER.sorted():
		var card := _CARD_SCENE.instantiate() as AmmoCard
		card.set_meta(&"reorder_key", t.id)
		_row.add_child(card)
		card.setup(t)
		card.set_stock(3, 1)
		card.set_count(1, 3)
	_settle.value_changed.connect(func(v: float) -> void: _row.settle_secs = v)
	_lift.value_changed.connect(func(v: float) -> void: _row.lift_scale = v)
	_row.order_changed.connect(_on_order_changed)
	_default_order.pressed.connect(_on_default_order)
	_on_order_changed(_row.ids())


func _on_order_changed(ids: Array[StringName]) -> void:
	_order_readout.text = "fires: " + " → ".join(PackedStringArray(ids))


func _on_default_order() -> void:
	var ids: Array[StringName] = []
	for t in _ROSTER.sorted():
		ids.append(t.id)
	_row.set_order(ids, true)
	_on_order_changed(_row.ids())


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
