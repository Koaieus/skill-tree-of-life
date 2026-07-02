extends Node2D

## Toast sandbox (#84) — a played showcase that spawns every [FloaterStyle] on
## demand so the whole toast catalogue can be eyeballed and debugged in isolation,
## the strikethrough shader chief among them. It drives the REAL renderer
## ([FloaterToasterManager]) with styles straight from [FloaterStyles.gallery] —
## the same library the [FloaterDirector] picks from — so what you see here is
## exactly what gameplay produces, and the two can't drift.
##
## The toaster only cares about WHERE: toasts anchor to a single [Marker2D] so a
## burst stacks (target-follow is optional in the real pipeline — no entity, no
## systems needed). One button row per gallery entry, each with +1 / +3.
##
## Registered as the "Toasts" tab of the sandbox host (#77) via
## tools/gen_sandbox_tabs.gd. Pre-composed in toast_showcase.tscn.

const FloaterStyles := preload("res://ui/floating_number_layer/floater_styles.gd")

@onready var _manager: FloaterToasterManager = $FloaterToasterManager
@onready var _anchor: Marker2D = $Anchor
@onready var _rows: VBoxContainer = %Rows


func _ready() -> void:
	($Camera2D as Camera2D).make_current()
	_build_rows()


## One row per style variant: "<name>   [+1] [+3]".
func _build_rows() -> void:
	for entry in FloaterStyles.gallery():
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 12)

		var name_label := Label.new()
		name_label.text = entry["name"]
		name_label.custom_minimum_size.x = 160
		row.add_child(name_label)

		row.add_child(_make_button("+1", entry, 1))
		row.add_child(_make_button("+3", entry, 3))
		_rows.add_child(row)


func _make_button(text: String, entry: Dictionary, count: int) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(_spawn.bind(entry, count))
	return btn


## Spawn [param count] toasts of this entry's style, anchored to the marker so a
## burst stacks. The toaster drains them one-per-fade_in so they read as a series.
func _spawn(entry: Dictionary, count: int) -> void:
	for i in count:
		var req := FloaterRequest.new()
		req.target = _anchor          # WHERE only — stacks the burst on one toaster
		req.text = entry["text"]
		req.style = entry["style"]
		_manager.spawn(req)
