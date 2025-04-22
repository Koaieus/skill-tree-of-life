extends MarginContainer
class_name ToolTip

var origin = ""
var target: TreeNode = null
var valid: bool = false

@onready var title_label: Label = $M/V/Title

var title: String

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	title_label.text = title if title else 'No Title'

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
