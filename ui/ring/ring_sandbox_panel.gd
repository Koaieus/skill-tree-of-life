@tool
extends PanelContainer
## Sandbox-host panel for [RingView]: the default ring, a button cycling the
## bought set through none / a few / many, and a log of hovered / clicked
## cell names. A click selects that cell. The view's knobs tune in its
## inspector; the bought set is grown by buying the first buyable cell, the
## way PoE adjacency allows.

## Cells bought at each cycle step. Tentative.
@export var bought_steps: PackedInt32Array = PackedInt32Array([0, 3, 12])

@onready var _view: RingView = %View
@onready var _log: Label = %Log
@onready var _cycle: Button = %Cycle

var _table: RingTable = null
var _step := 0
var _selected: StringName = &""


func _ready() -> void:
	_table = RingTable.sample(_view.display_graph())
	_cycle.pressed.connect(_on_cycle)
	_view.cell_hovered.connect(_on_hovered)
	_view.cell_clicked.connect(_on_clicked)
	_show()


func _spent() -> Array[StringName]:
	var spent: Array[StringName] = []
	var want := bought_steps[_step] if _step < bought_steps.size() else 0
	while spent.size() < want:
		var open := _table.buyable(spent)
		if open.is_empty():
			break
		spent.append(open[0])
	return spent


func _show() -> void:
	var spent := _spent()
	_cycle.text = "Bought: %d (cycle)" % spent.size()
	_view.show_state(_table, spent, _selected)


func _on_cycle() -> void:
	_step = (_step + 1) % maxi(bought_steps.size(), 1)
	_show()


func _on_hovered(cell: StringName) -> void:
	_log.text = "hover: %s" % (cell if cell != &"" else &"—")


func _on_clicked(cell: StringName) -> void:
	_selected = cell
	_log.text = "click: %s" % (cell if cell != &"" else &"—")
	_show()
