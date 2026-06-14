## Inspector entry-point: appends an "Open in VFX Playground" button to any
## selected [VFXCoordinator]. Click → `playground_requested` → `plugin.gd`
## reveals the bottom panel and hands it the live coord reference.
@tool
extends EditorInspectorPlugin

signal playground_requested(coord: VFXCoordinator)


func _can_handle(object: Object) -> bool:
	return object is VFXCoordinator


func _parse_begin(object: Object) -> void:
	var coord := object as VFXCoordinator
	var btn := Button.new()
	btn.text = "  Open in VFX Playground"
	btn.icon = EditorInterface.get_editor_theme().get_icon(&"Play", &"EditorIcons")
	btn.tooltip_text = "Fire this coordinator at the playground's preset targets — read its current exports as the source of truth, no separate UI."
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.pressed.connect(func() -> void: playground_requested.emit(coord))
	add_custom_control(btn)
