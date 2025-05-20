extends HBoxContainer
class_name StatRow

@export var stat: Stat

@onready var progress_bar: DecoratedProgressBar = %ProgressBar

@export var text_display: String:
	get(): return text_display
	set(value):
		if text_display != value:
			#print('setting row text to "%s"' % value)
			text_display = value
			$LabelText.text = text_display

@export var value_display: String:
	get(): return value_display
	set(value):
		if value_display != value:
			#print('setting row value to "%s"' % value)
			value_display = value
			$LabelValue.text = value_display

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
