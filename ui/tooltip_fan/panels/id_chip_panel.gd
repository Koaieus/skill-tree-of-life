@tool
class_name IdChipPanel
extends FanPanel

## Tooltip V2 (#226/#232) — the ID chip: node id/degree, near the node, with
## its OWN trace ("it belongs to the sprout rather than floating free" — the
## only reason it gets a full [FanUnit] pair instead of hanging directly off
## the node like the old single-card tooltip did). Small and fixed-size;
## placeholder text only. The node-name generator this eventually reads from
## is #288 (was miscited as "its own issue" before #288 existed — see #226's
## "Two corrections" issue comment).

@onready var _label: Label = %Label


func _ready() -> void:
	super._ready()
	_label.text = "#-- · deg -"
