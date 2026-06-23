## Inspector hook: whenever a [SpellDef] is the currently-inspected object,
## emit [signal spell_inspected] so the plugin can sync the bottom panel.
## Also appends a small "Open Spell Playground" button that just reveals the
## panel — the spell ref is pushed automatically, no manual loading needed.
@tool
extends EditorInspectorPlugin

signal spell_inspected(spell: SpellDef)
signal reveal_panel_requested


func _can_handle(object: Object) -> bool:
	return object is SpellDef


func _parse_begin(object: Object) -> void:
	var spell := object as SpellDef
	spell_inspected.emit(spell)
	var btn := Button.new()
	btn.text = "  Open Spell Playground"
	btn.icon = EditorInterface.get_editor_theme().get_icon(&"Play", &"EditorIcons")
	btn.tooltip_text = "Reveal the Spell Playground bottom panel. The panel auto-syncs with whichever SpellDef is selected — no manual load step."
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.pressed.connect(func() -> void: reveal_panel_requested.emit())
	add_custom_control(btn)
