extends MarginContainer
class_name ToolTip

var origin = ""
var target: TreeNode = null
var valid: bool = false

@onready var title_label: Label = %Title
@onready var contents: VBoxContainer = %Contents

var title: String

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_title(title)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func set_title(title: String) -> void:
	title_label.text = title if title else 'No Title'

func clear_lines() -> void:
	for child in %Contents.get_children():
		child.queue_free()

func add_line(text: String) -> void:
	var label = Label.new()
	label.text = text
	%Contents.add_child(label)

func set_lines(lines: Array[String]) -> void:
	clear_lines()
	for line in lines:
		add_line(line)
