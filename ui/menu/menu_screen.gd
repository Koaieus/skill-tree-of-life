class_name MenuScreen
extends Control

## Base skeleton for a single "level" of the meta-menu breadcrumb.
## Builds its own chrome (background, title, back button) in code — same
## code-composed-UI convention as [SettingsMenu] — so concrete screens are
## thin subclasses with no scene file. See [MenuStack] for how these get
## panned/shrunk when a new level is pushed.

signal back_requested

@export var panel_size: Vector2 = Vector2(360, 520)

var content: VBoxContainer
var back_button: Button

var _title_label: Label


func _ready() -> void:
	custom_minimum_size = panel_size
	size = panel_size
	clip_contents = true

	var background := ColorRect.new()
	background.color = Color(0.05, 0.06, 0.09, 0.85)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var layout := VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 16
	layout.offset_top = 16
	layout.offset_right = -16
	layout.offset_bottom = -16
	layout.add_theme_constant_override("separation", 12)
	add_child(layout)

	_title_label = Label.new()
	_title_label.theme_type_variation = &"CinzelHeader"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(_title_label)

	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	layout.add_child(content)

	back_button = Button.new()
	back_button.text = "Back"
	back_button.pressed.connect(func(): back_requested.emit())
	layout.add_child(back_button)


func set_title(title: String) -> void:
	_title_label.text = title


## Adds a Button to [member content]. Caller connects `.pressed` itself.
func add_option(text: String, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = disabled
	content.add_child(button)
	return button


## Called by [MenuStack] on relayout: only the top-of-stack screen accepts
## input. Toggling `mouse_filter` (rather than `disabled`) so a genuinely
## disabled option (e.g. "Load Game") doesn't get silently re-enabled when
## its screen becomes active again.
func set_interactive(active: bool) -> void:
	var filter := Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
	var focus := Control.FOCUS_ALL if active else Control.FOCUS_NONE
	for button in content.get_children():
		if button is Control:
			button.mouse_filter = filter
			button.focus_mode = focus
	back_button.mouse_filter = filter
	back_button.focus_mode = focus
