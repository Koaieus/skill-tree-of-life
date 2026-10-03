@tool
class_name LoadPanel
extends FrontmatterPanel

## LOAD GAME — the frontmatter's way back into a saved run. One slot, so one
## button: it is live when the slot exists, and a press goes through [SavedRun],
## the same path the pause menu's LOAD takes. A refused file stays here and the
## status line says why; nothing is half-opened.

## The slot this panel offers. Exported so a test can point it elsewhere.
@export var slot_path: String = SaveFile.SLOT_PATH

@onready var _status: Label = %Status
@onready var _load_button: Button = %LoadButton


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	_load_button.pressed.connect(_on_load_pressed)
	visibility_changed.connect(refresh)
	refresh()


## Re-read whether there is a slot. On every reveal, since a run saved and
## abandoned since the menu was built has to show up.
func refresh() -> void:
	var has_slot := SavedRun.has_slot(slot_path)
	_load_button.disabled = not has_slot
	# A disabled button must not take the keyboard a panel hands its first
	# focusable on reveal.
	_load_button.focus_mode = Control.FOCUS_ALL if has_slot else Control.FOCUS_NONE
	_status.text = "" if has_slot else SavedRun.describe(SaveFile.LoadResult.MISSING)
	_status.visible = not has_slot


func _on_load_pressed() -> void:
	var save := SavedRun.open(slot_path)
	if save.load_result != SaveFile.LoadResult.OK:
		_status.text = SavedRun.describe(save.load_result)
		_status.visible = true
		return
	SavedRun.route(save)
