extends GutTest
## Covers #144: a live-edit panel can emit `reload_requested` to have its tab
## rebuilt from scratch — the "stuck cast lock" escape hatch that a
## health-refill Reset button can't provide.
##
## Since #881 the WHOLE TAB is the unit of reload: the tab asks its composing
## `SandboxHost` to rebuild it from its own `.tscn` (`reload_tab`), so the test
## mounts the tab inside a minimal host — a bare tab has nobody to ask and
## reload is (correctly) a no-op there.


## A SandboxHost that does not auto-discover every tab under tabs/ on ready —
## the reload path is what's under test, not the registry scan.
class _BareHost extends SandboxHost:
	func _ready() -> void:
		_tabs = $Tabs


var _host: SandboxHost


func before_each() -> void:
	_host = _BareHost.new()
	var tabs := TabContainer.new()
	tabs.name = "Tabs"
	_host.add_child(tabs)
	var scene: PackedScene = load("res://addons/sandbox_host/tabs/10_spell_tab.tscn")
	tabs.add_child(scene.instantiate())
	add_child(_host)
	await get_tree().process_frame


func after_each() -> void:
	_host.queue_free()


## The live tab currently mounted — a fresh node after a reload.
func _tab() -> SandboxLiveTab:
	return _host.get_node("Tabs").get_child(0) as SandboxLiveTab


## The panel baked under the tab's `%PanelHost` slot.
func _embedded_panel() -> Node:
	return _tab().get_node(^"%PanelHost").get_child(0)


func test_panel_declares_reload_requested() -> void:
	var panel := _embedded_panel()
	assert_true(panel.has_signal(&"reload_requested"),
		"spell playground panel should expose reload_requested (#144)")


func test_emitting_reload_requested_swaps_the_panel_instance() -> void:
	var panel := _embedded_panel()
	var original_id := panel.get_instance_id()

	panel.reload_requested.emit()
	await get_tree().process_frame

	var reloaded := _embedded_panel()
	assert_ne(reloaded.get_instance_id(), original_id, "reload should be a fresh instance, not the same node")
	assert_eq(_host.get_node("Tabs").get_child_count(), 1, "the tab is replaced in place, not duplicated")


func test_reload_redelivers_the_last_loaded_object() -> void:
	var spell: SpellDef = load("res://attack/spell/defs/spark.tres")
	_tab().load_object(spell)

	var panel := _embedded_panel()
	panel.reload_requested.emit()
	await get_tree().process_frame

	var reloaded := _embedded_panel()
	assert_false(reloaded.status_label.text.begins_with("No spell"),
		"reloaded panel should not fall back to the no-spell-loaded state")
	assert_true(reloaded.status_label.text.begins_with(spell.name),
		"reloaded panel should have the previously-loaded spell re-delivered via load_spell")
