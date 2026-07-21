@tool
class_name ToastCell
extends SubViewportContainer

## One toast-preview cell: a SubViewport with a tinted background, a small
## debug label, and a [FloaterToaster] anchored center. Extracted (#265) from
## [code]ToastSandboxPanel._build_cells()[/code]'s hand-built 7-node subtree
## (SubViewportContainer > SubViewport > ColorRect + Label + Control(anchor)
## + FloaterToaster) so the grid can loop-instantiate this scene instead.

const _TOASTER_SCENE: PackedScene = preload("res://ui/floating_number_layer/floater_toaster.tscn")

## Background tint for this cell — subtle, so it reads as distinct without a
## heavy border.
@export var tint: Color = Color(0.14, 0.14, 0.16, 1.0):
	set(value):
		tint = value
		if _background:
			_background.color = value

## Debug label text drawn in the top-left corner of the cell (the gallery
## entry name, or "Random").
@export var label_text: String = "":
	set(value):
		label_text = value
		if _label:
			_label.text = value

## The toaster this cell drives. Instantiated in [method _ready]; use
## [method get_or_remake_toaster] if it may have been freed.
var toaster: FloaterToaster

@onready var _background: ColorRect = $Viewport/Background
@onready var _label: Label = $Viewport/Label
@onready var _anchor: Control = $Viewport/ToastAnchor


func _ready() -> void:
	_background.color = tint
	_label.text = label_text
	if Engine.is_editor_hint():
		return  # don't spawn a live toaster into the edited scene
	_spawn_toaster()


func _spawn_toaster() -> void:
	toaster = _TOASTER_SCENE.instantiate()
	toaster.max_queue_size = 16
	_anchor.add_child(toaster)


## Returns the live toaster, recreating it if it was freed or removed from
## the tree (mirrors the old ToastSandboxPanel._remake_toaster behaviour).
func get_or_remake_toaster() -> FloaterToaster:
	if not is_instance_valid(toaster) or not toaster.is_inside_tree():
		_spawn_toaster()
	return toaster
