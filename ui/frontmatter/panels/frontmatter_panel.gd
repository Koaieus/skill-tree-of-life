@tool
class_name FrontmatterPanel
extends Control

## One screen on the frontmatter's `%PanelLayer` — the lobby, the settings, the
## join prompt, the parked load screen, the exit confirm (#573).
##
## [b]This is a base scene, and it earns its keep by packaging children.[/b]
## Per `.claude/rules/scene-composition.md`, every concrete panel is an
## [i]inherited scene[/i] of `frontmatter_panel.tscn` that fills [member body];
## none of them compose their own backdrop, frame, title or back button, so a
## structural change to the chrome propagates to all five for free. That is the
## opposite of what this replaces: the deleted `MenuScreen` built the same
## chrome in `_ready` with `X.new()` chains, which is why its subclasses had no
## scene files at all.
##
## [b]A panel never knows where the camera is.[/b] It lives under a
## [CanvasLayer], which is immune to the graph camera's pan and zoom by design
## — that is the whole reason #567 split the two layers, and the reason panel
## text stays crisp and stationary while the tree moves behind it. Nothing here
## may reach for [Camera2D], the graph layer, or [FrontmatterPanels] itself.
##
## A panel asks to be dismissed; it does not dismiss itself. [signal dismissed]
## goes up to [FrontmatterPanels], which re-emits it as
## [signal FrontmatterPanels.panel_dismissed] for the navigation state machine
## to act on — the panel has no idea what "back" means in graph terms.

## Emitted when this panel wants the frontmatter to return to the graph.
## [FrontmatterPanels] relays it, tagged with [member panel_id].
signal dismissed

## Which [MenuGraph] panel id this scene answers to — `MenuGraph.PANEL_LOBBY`
## and friends. [FrontmatterPanels] reads it off each child at `_ready` to build
## its registry, so a new panel is registered by [i]existing in the scene[/i]
## with this set, never by editing a table.
@export var panel_id: StringName = &"":
	set = _set_panel_id

## The all-caps heading. Authored per inherited scene; empty hides the label.
@export var title: String = "":
	set = _set_title

## Label under the back button, so a panel can name its own escape ("BACK",
## "CANCEL"). Empty hides the button entirely — a panel that must be answered
## rather than escaped.
@export var back_text: String = "BACK":
	set = _set_back_text

## Where an inherited scene puts its content. Pre-packaged by this scene, so an
## inherited scene may rely on it existing.
@onready var body: VBoxContainer = %Body
@onready var back_button: Button = %BackButton

@onready var _title_label: Label = %Title


func _ready() -> void:
	_apply_title()
	_apply_back_text()
	if not Engine.is_editor_hint():
		back_button.pressed.connect(_on_back_pressed)


func _set_panel_id(value: StringName) -> void:
	panel_id = value


func _set_title(value: String) -> void:
	title = value
	_apply_title()


func _set_back_text(value: String) -> void:
	back_text = value
	_apply_back_text()


func _apply_title() -> void:
	if not is_node_ready():
		return
	_title_label.text = title
	_title_label.visible = title != ""


func _apply_back_text() -> void:
	if not is_node_ready():
		return
	back_button.text = back_text
	back_button.visible = back_text != ""


## Emit [signal dismissed]. Exposed so an inherited scene can route its own
## "cancel" affordance through the same exit as the back button rather than
## re-emitting the signal itself.
func dismiss() -> void:
	dismissed.emit()


func _on_back_pressed() -> void:
	dismiss()
