extends GutTest
## The host builds a tab only when it is both visible and selected, and keeps at
## most one built: the editor starts the plugin on launch, and most sessions
## never open the Sandbox screen.

const _HOST_SCENE := "res://addons/sandbox_host/sandbox_host.tscn"

var _host: SandboxHost


func before_each() -> void:
	_host = load(_HOST_SCENE).instantiate()
	_host.hide()
	add_child(_host)
	await get_tree().process_frame


func after_each() -> void:
	_host.queue_free()


func _tabs() -> TabContainer:
	return _host.get_node(^"Tabs")


func _built_indices() -> Array:
	var out: Array = []
	for child in _tabs().get_children():
		if child is SandboxTab:
			out.append(child.get_index())
	return out


func _index_of(title: String) -> int:
	for i in _tabs().get_tab_count():
		if _tabs().get_tab_title(i) == title:
			return i
	return -1


func test_a_hidden_host_builds_no_tab_but_titles_them_all() -> void:
	assert_gt(_tabs().get_tab_count(), 0)
	assert_eq(_built_indices(), [], "a hidden host must not build any tab")
	assert_ne(_index_of("Spell"), -1, "an unbuilt tab still carries its title")


func test_showing_builds_only_the_current_tab() -> void:
	_tabs().current_tab = _index_of("Bloom")
	_host.show()
	await get_tree().process_frame
	assert_eq(_built_indices(), [_index_of("Bloom")])


func test_switching_tabs_keeps_one_built() -> void:
	_host.show()
	_tabs().current_tab = _index_of("Bloom")
	await get_tree().process_frame
	_tabs().current_tab = _index_of("Toasts")
	await get_tree().process_frame
	assert_eq(_built_indices(), [_index_of("Toasts")])


func test_a_route_to_an_unbuilt_tab_is_delivered_when_it_is_revealed() -> void:
	var spell: SpellDef = load("res://attack/spell/defs/spark.tres")
	_host.route_to(&"spell", spell)
	assert_eq(_built_indices(), [], "a passive route must not build the tab")

	_host.show()
	_host.reveal_tab(&"spell")
	await get_tree().process_frame

	var tab := _tabs().get_child(_index_of("Spell")) as SandboxLiveTab
	assert_not_null(tab, "reveal_tab builds the tab")
	var panel: Node = tab.get_node(^"%PanelHost").get_child(0)
	assert_true(panel.status_label.text.begins_with(spell.name),
		"the stashed spell is delivered on build")
