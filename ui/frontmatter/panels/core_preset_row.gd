class_name CorePresetRow
extends HBoxContainer
## The AI core preset row (#841): one control that templates every AI slot's
## default core class, above the roster rows.
##
## Modeled on [AiCountRow] — a label plus one control, one `value_changed`-
## style signal the screen wires to a rebuild/repaint, nothing else. Unlike
## the count row this control's "off" position is meaningful on its own: the
## FIRST entry is a sentinel meaning "no preset" (owner, 2026-09-10 —
## "preset row should get a sentinel... such that things don't change too
## much"), and it is the control's initial value. While it is selected this
## row templates nothing and the lobby behaves exactly as it did before this
## feature — see [method LobbyScreen.apply_core_preset]'s `null` branch.

## The preset changed. `null` is the sentinel ("no preset") — never a real
## [CoreClass] that merely reads as "off"; the sentinel is its own dropdown
## entry, not inferred from an empty selection.
signal preset_changed(core: CoreClass)

const _SENTINEL_LABEL := "(no preset)"

@onready var _pick: OptionButton = %Pick


func _ready() -> void:
	_pick.item_selected.connect(_on_item_selected)


## Fill the dropdown with [param cores], sentinel first and selected — arming
## the preset is something the player opts into, never the row's own doing.
func set_choices(cores: Array[CoreClass]) -> void:
	_pick.clear()
	_pick.add_item(_SENTINEL_LABEL)
	_pick.set_item_metadata(0, null)
	for i in cores.size():
		var core: CoreClass = cores[i]
		_pick.add_item(core.display_name if core.display_name != "" else core.resource_path.get_file())
		_pick.set_item_metadata(i + 1, core)
	_pick.select(0)


func _on_item_selected(index: int) -> void:
	var core: Variant = _pick.get_item_metadata(index)
	preset_changed.emit(core if core is CoreClass else null)
