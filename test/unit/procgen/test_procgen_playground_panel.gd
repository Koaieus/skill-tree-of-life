extends GutTest
## Acceptance contract for the procgen playground panel's scenic rebuild
## (#264) — `playground_panel.tscn` used to be a bare `Control` with the whole
## tree hand-welded in `_build_ui`/`_build_map_tab`/`_build_graph_tab`. Locks
## that the authored `.tscn` tree is what the script now resolves via
## `%unique_name`, not something it still builds itself.

const _PANEL := "res://procgen/playground/playground_panel.tscn"
const _PRESET := preload("res://procgen/presets/first_level/first_level.tres")


func test_scene_is_genuinely_scenic_before_ready() -> void:
	# %-nodes must already exist straight out of instantiate() — before _ready
	# has run — proving the tree is authored in the .tscn, not code-built.
	var panel: Control = load(_PANEL).instantiate()
	assert_not_null(panel.get_node_or_null(^"%Sidebar"),
		"%Sidebar must resolve from the packed scene, pre-_ready")
	assert_not_null(panel.get_node_or_null(^"%Tabs"),
		"%Tabs must resolve from the packed scene, pre-_ready")
	panel.free()


func test_all_unique_nodes_resolve_with_expected_types() -> void:
	var panel: Control = load(_PANEL).instantiate()
	add_child(panel)
	await get_tree().process_frame

	assert_true(panel.get_node(^"%Sidebar") is VBoxContainer, "%Sidebar must be a VBoxContainer")
	assert_true(panel.get_node(^"%Tabs") is TabContainer, "%Tabs must be a TabContainer")
	assert_true(panel.get_node(^"%MapTab") is VBoxContainer, "%MapTab must be a VBoxContainer")
	assert_true(panel.get_node(^"%GraphTab") is VBoxContainer, "%GraphTab must be a VBoxContainer")

	var map_view: Node = panel.get_node(^"%MapView")
	assert_not_null(map_view, "%MapView must resolve")
	assert_true(map_view.has_signal(&"map_clicked"), "%MapView must carry field_map_view.gd (map_clicked signal)")

	var graph_view: Node = panel.get_node(^"%GraphView")
	assert_not_null(graph_view, "%GraphView must resolve")
	assert_true(graph_view.has_signal(&"node_clicked"), "%GraphView must carry node_graph_view.gd (node_clicked signal)")

	assert_true(panel.get_node(^"%MapCardsRow") is HBoxContainer, "%MapCardsRow must be an HBoxContainer")
	assert_true(panel.get_node(^"%GraphCardsRow") is HBoxContainer, "%GraphCardsRow must be an HBoxContainer")
	assert_eq(panel.get_node(^"%MapCardsRow").get_child_count(), 5, "map cards row must hold 5 sample cards")
	assert_eq(panel.get_node(^"%GraphCardsRow").get_child_count(), 5, "graph cards row must hold 5 sample cards")

	assert_true(panel.get_node(^"%ArchOption") is OptionButton)
	assert_true(panel.get_node(^"%BoundLabel") is Label)
	assert_true(panel.get_node(^"%SeedLabel") is Label)
	assert_true(panel.get_node(^"%OpenPresetsFolderButton") is Button)
	assert_true(panel.get_node(^"%ReseedButton") is Button)
	assert_true(panel.get_node(^"%GraphNodeCountSpin") is SpinBox)
	assert_true(panel.get_node(^"%RegenerateGraphButton") is Button)
	assert_true(panel.get_node(^"%StampArchOption") is OptionButton)
	assert_true(panel.get_node(^"%StampRadiusSpin") is SpinBox)
	assert_true(panel.get_node(^"%StampPaintToggle") is Button)
	assert_true(panel.get_node(^"%StampClearButton") is Button)

	panel.queue_free()


func test_tab_titles_are_map_sample_and_node_graph() -> void:
	var panel: Control = load(_PANEL).instantiate()
	add_child(panel)
	await get_tree().process_frame

	var tabs: TabContainer = panel.get_node(^"%Tabs")
	var map_tab: Control = panel.get_node(^"%MapTab")
	var graph_tab: Control = panel.get_node(^"%GraphTab")
	assert_eq(tabs.get_tab_title(map_tab.get_index()), "Map Sample")
	assert_eq(tabs.get_tab_title(graph_tab.get_index()), "Node Graph")

	panel.queue_free()


func test_load_config_and_refresh_do_not_error() -> void:
	var panel = load(_PANEL).instantiate()
	add_child(panel)
	await get_tree().process_frame

	panel.load_config(_PRESET)
	await get_tree().process_frame
	panel.refresh_from_config()
	await get_tree().process_frame

	pass_test("load_config + refresh_from_config completed without error")
	panel.queue_free()
