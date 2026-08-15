@tool
class_name ManageCard
extends PanelContainer
## One Manage-tab quick-action card (#338): a title + hint label, clickable
## via a flat overlay Button, with an optional toggled "armed" affordance.
## Reused 5x by manage_body.tscn (Allocate/Move Core/Deallocate/Stake/Extract)
## instead of hand-authoring five near-identical PanelContainer subtrees
## (.claude/rules/scene-composition.md).

signal pressed

@export var title_text: String = "":
	set(value):
		title_text = value
		if is_node_ready():
			_title.text = value

@export var hint_text: String = "":
	set(value):
		hint_text = value
		if is_node_ready():
			_hint.text = value

@export var title_color: Color = Color.WHITE:
	set(value):
		title_color = value
		if is_node_ready():
			_title.modulate = value

## Whether this card reflects an on/off armed state (Allocate/Deallocate/
## Stake/Extract/Move Core all do) vs. being a plain button. All five current
## uses set this true; kept as an export rather than assumed so a future
## non-toggling card doesn't need a workaround.
@export var toggle_mode: bool = true:
	set(value):
		toggle_mode = value
		if is_node_ready():
			_button.toggle_mode = value

@onready var _button: Button = %Button
@onready var _title: Label = %Title
@onready var _hint: Label = %Hint


func _ready() -> void:
	_button.pressed.connect(func() -> void: pressed.emit())
	_title.text = title_text
	_title.modulate = title_color
	_hint.text = hint_text
	_button.toggle_mode = toggle_mode


## Reflects the card's armed/active state — brightens the card so the
## currently-armed verb reads as pressed, cleared cursor-style feedback lives
## in PlayerInputController._update_cursor instead of here.
func set_armed(value: bool) -> void:
	if _button != null:
		_button.button_pressed = value
	self_modulate = Color(1.35, 1.35, 1.35, 1) if value else Color(1, 1, 1, 1)
