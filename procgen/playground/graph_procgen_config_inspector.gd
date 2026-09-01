## Inspector hook: whenever a [GraphProcgenConfig] is the currently-inspected
## object, emit [signal config_inspected] so the plugin can sync the Procgen
## Playground tab. Also appends an "Open Procgen Playground" button that just
## reveals the tab — the config ref is pushed automatically, no manual load.
@tool
extends EditorInspectorPlugin

signal config_inspected(config: GraphProcgenConfig)
signal reveal_panel_requested


func _can_handle(object: Object) -> bool:
	return object is GraphProcgenConfig


func _parse_begin(object: Object) -> void:
	var config := object as GraphProcgenConfig
	config_inspected.emit(config)
	var btn := Button.new()
	btn.text = "  Open Procgen Playground"
	btn.icon = Engine.get_singleton(&"EditorInterface").get_editor_theme().get_icon(&"Play", &"EditorIcons")
	btn.tooltip_text = "Reveal the Procgen Playground tab. It auto-syncs with whichever GraphProcgenConfig is selected, and re-renders live as you tweak its properties."
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.pressed.connect(func() -> void: reveal_panel_requested.emit())
	add_custom_control(btn)
