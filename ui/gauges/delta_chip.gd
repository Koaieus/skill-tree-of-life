@tool
class_name DeltaChip
extends PanelContainer
## Shared "up-arrow +N / down-arrow -N" pop-in chip (design's chipIn
## animation, 2.7s lifetime). One component, two call sites — Attribute
## rows and Combat Readout cards — per the reusable-contracts brief.

const LIFETIME := 2.7
const POP_TIME := 0.25

@export var positive_color: Color = Color(0.55, 0.85, 0.6, 1.0)
@export var negative_color: Color = Color(0.95, 0.45, 0.45, 1.0)

## Preview the pop-in/fade-out in the editor via the Inspector button.
@export_tool_button("Preview +N") var _preview_positive_action := pop.bind(3.0)
@export_tool_button("Preview -N") var _preview_negative_action := pop.bind(-2.0)

@onready var _label: Label = %Label

var _hide_timer: SceneTreeTimer
var _tween: Tween

func _ready() -> void:
	modulate.a = 0.0
	visible = false

## Pops the chip in showing `delta` (sign determines color/arrow), then
## auto-hides after LIFETIME seconds. Safe to call in-editor for preview.
func pop(delta: float) -> void:
	if not is_inside_tree():
		return
	var positive := delta >= 0.0
	var arrow := "▲" if positive else "▼"
	var sign_str := "+" if positive else ""
	_label.text = "%s%s%d" % [arrow, sign_str, int(delta)]
	_label.modulate = positive_color if positive else negative_color

	visible = true
	scale = Vector2(0.8, 0.8)
	position.y += 3.0
	modulate.a = 0.0

	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, ^"modulate:a", 1.0, POP_TIME)
	_tween.tween_property(self, ^"scale", Vector2.ONE, POP_TIME)
	_tween.tween_property(self, ^"position:y", position.y - 3.0, POP_TIME)
	_tween.chain().tween_callback(_start_hide_timer)

func _start_hide_timer() -> void:
	var tree := get_tree()
	if tree == null:
		return
	_hide_timer = tree.create_timer(LIFETIME - POP_TIME)
	_hide_timer.timeout.connect(_fade_out)

func _fade_out() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, ^"modulate:a", 0.0, POP_TIME)
	_tween.tween_callback(func(): visible = false)
