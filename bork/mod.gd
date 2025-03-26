@tool
extends HBoxContainer

enum Stat {STR, INT, DEX, HEALTH}
enum Op {INCREMENT, INCREASE, MULTIPLY, SET}


@export_category('Mod Config')
@export var amount: float = 0:
	get:
		return amount
	set(value):
		amount = value
		#_update_text()
		
@export var stat: Stat = Stat.STR:
	get:
		return stat
	set(value):
		stat = value
		#_update_text()
		
@export var operation: Op = Op.INCREMENT:
	get:
		return operation
	set(value):
		operation = value
		#_update_text()

const OPERATION_DISPLAY: Dictionary = {
	Op.INCREMENT: "+{amount} {stat}",
	Op.INCREASE: "+{amount}% {stat}",
	Op.MULTIPLY: "{stat} x{amount}",
	Op.SET: "Set {stat} to {amount}"
}




# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_update_text()
	
	#for stat in Stat:
		#$StatPicker.add_item()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _update_text() -> void:
	$Label.text = OPERATION_DISPLAY[operation].format({stat = Stat.keys()[stat], amount = amount})
	
func _on_delete_button_click() -> void:
	self.queue_free()
