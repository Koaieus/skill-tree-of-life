extends GutTest
## Covers #144: a live-edit panel can emit `reload_requested` to have the
## composing SandboxLiveTab discard and re-instantiate it — the "stuck cast
## lock" escape hatch that a health-refill Reset button can't provide.

var _tab: SandboxLiveTab


func before_each() -> void:
	var scene: PackedScene = load("res://addons/sandbox_host/tabs/10_spell_tab.tscn")
	_tab = scene.instantiate()
	add_child(_tab)
	await get_tree().process_frame


func after_each() -> void:
	_tab.queue_free()


func test_panel_declares_reload_requested() -> void:
	var panel := _tab.get_child(0)
	assert_true(panel.has_signal(&"reload_requested"),
		"spell playground panel should expose reload_requested (#144)")


func test_emitting_reload_requested_swaps_the_panel_instance() -> void:
	var panel := _tab.get_child(0)
	var original_id := panel.get_instance_id()

	panel.reload_requested.emit()
	await get_tree().process_frame

	assert_eq(_tab.get_child_count(), 1, "reload should leave exactly one embedded panel")
	var reloaded := _tab.get_child(0)
	assert_ne(reloaded.get_instance_id(), original_id, "reload should be a fresh instance, not the same node")


func test_reload_redelivers_the_last_loaded_object() -> void:
	var spell: SpellDef = load("res://attack/spell/defs/spark.tres")
	_tab.load_object(spell)

	var panel := _tab.get_child(0)
	panel.reload_requested.emit()
	await get_tree().process_frame

	var reloaded := _tab.get_child(0)
	assert_false(reloaded.status_label.text.begins_with("No spell"),
		"reloaded panel should not fall back to the no-spell-loaded state")
	assert_true(reloaded.status_label.text.begins_with(spell.name),
		"reloaded panel should have the previously-loaded spell re-delivered via load_spell")
