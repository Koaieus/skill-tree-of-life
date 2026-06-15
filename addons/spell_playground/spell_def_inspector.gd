## Inspector entry-point: appends an "Open in Spell Playground" button to any
## selected [SpellDef]. Click → `playground_requested` → `plugin.gd` reveals
## the bottom panel and hands it the live spell reference.
@tool
extends EditorInspectorPlugin

signal playground_requested(spell: SpellDef)


func _can_handle(object: Object) -> bool:
	return object is SpellDef


func _parse_begin(object: Object) -> void:
	var spell := object as SpellDef
	var btn := Button.new()
	btn.text = "  Open in Spell Playground"
	btn.icon = EditorInterface.get_editor_theme().get_icon(&"Play", &"EditorIcons")
	btn.tooltip_text = "Cast this spell at a target on a small isolated graph — read its current exports as the source of truth, watch propagation and VFX without the full battle pipeline."
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.pressed.connect(func() -> void: playground_requested.emit(spell))
	add_custom_control(btn)
