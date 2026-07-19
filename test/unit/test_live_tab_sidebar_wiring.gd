extends GutTest
## Live tabs that adopt a %Sidebar DirectoryCardList (#253): the sidebar is shown
## and its selection self-wires to the tab's load_object via the base.


func _load(tab_path: String) -> SandboxLiveTab:
	var t: SandboxLiveTab = load(tab_path).instantiate()
	add_child(t)
	return t


func _card_list(tab: SandboxLiveTab) -> DirectoryCardList:
	for c in tab.get_node(^"%Sidebar").get_children():
		if c is DirectoryCardList:
			return c
	return null


func test_spell_tab_shows_sidebar_wired_to_loader() -> void:
	var tab := _load("res://addons/sandbox_host/tabs/10_spell_tab.tscn")
	await get_tree().process_frame
	assert_true(tab.get_node(^"%Sidebar").visible, "spell tab sidebar should be visible")
	var list := _card_list(tab)
	assert_not_null(list, "spell tab should carry a DirectoryCardList in %Sidebar")
	assert_gt(list.entries().size(), 0, "should list the spell defs")
	assert_true(list.is_connected("selected_resource", Callable(tab, "load_object")),
		"base must self-wire the card list to load_object")
	tab.queue_free()
