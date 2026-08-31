class_name LabelledRow
extends HBoxContainer

## A label beside an expanding field (#690) — the shape `settings_menu.gd`,
## `host_join_screen.gd`, and `lobby_screen.gd` were each hand-building as a
## fresh `HBoxContainer` + `Label` + field. One scene, one swap
## implementation; every caller instances this and calls [method set_widget].


func set_label(text: String) -> void:
	(%Label as Label).text = text


## Swaps the placeholder `%Widget` slot for [param widget] and returns it.
##
## The slot's own size flag is the default a widget gets — but only if it
## didn't already claim one of its own (CheckBox, OptionButton); Control's own
## stock default is SIZE_FILL, so anything still sitting at that means the
## caller left it alone.
func set_widget(widget: Control) -> Control:
	var slot := %Widget as Control
	if widget.size_flags_horizontal == Control.SIZE_FILL:
		widget.size_flags_horizontal = slot.size_flags_horizontal
	var slot_index := slot.get_index()
	remove_child(slot)
	slot.queue_free()
	add_child(widget)
	move_child(widget, slot_index)
	return widget
