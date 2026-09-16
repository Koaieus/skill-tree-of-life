extends GutTest
## Locks the SandboxLiveTab base contract the #252/#253/#254 component layer
## builds on: the collapsed %Sidebar slot, the %PanelHost slot, and the
## adopt-or-instance panel mount (#254).

const _BASE := "res://addons/sandbox_host/sandbox_live_tab.tscn"


func test_base_exposes_collapsed_sidebar_and_panel_host() -> void:
	var tab: SandboxLiveTab = load(_BASE).instantiate()
	var sidebar := tab.get_node_or_null(^"%Sidebar")
	var panel_host := tab.get_node_or_null(^"%PanelHost")
	assert_not_null(sidebar, "base must expose a %Sidebar slot")
	assert_not_null(panel_host, "base must expose a %PanelHost slot")
	assert_false(sidebar.visible, "%Sidebar must be collapsed by default (single-column look)")
	tab.free()


## The collapsed HSplit must not steal width from %PanelHost — this is what keeps
## the 4 sidebar-less tabs (vfx/statboard/node_visuals/gimbal_3d) visually
## unchanged after the base gained the split. Headless-computable layout fact.
func test_collapsed_split_leaves_panel_full_width() -> void:
	var holder := Control.new()
	holder.size = Vector2(800, 600)
	add_child(holder)
	var tab: SandboxLiveTab = load(_BASE).instantiate()
	holder.add_child(tab)
	await get_tree().process_frame

	var split: Control = tab.get_node(^"Layout/Split")
	var host: Control = tab.get_node(^"%PanelHost")
	assert_almost_eq(host.size.x, split.size.x, 4.0,
		"collapsed HSplit must not offset the panel")
	holder.queue_free()


## And a shown sidebar with content actually shrinks the panel — locks the
## expectation for a future card tab.
func test_visible_sidebar_shrinks_panel() -> void:
	var holder := Control.new()
	holder.size = Vector2(800, 600)
	add_child(holder)
	var tab: SandboxLiveTab = load(_BASE).instantiate()
	holder.add_child(tab)
	var sidebar: Control = tab.get_node(^"%Sidebar")
	sidebar.custom_minimum_size = Vector2(150, 0)
	sidebar.visible = true
	await get_tree().process_frame

	var split: Control = tab.get_node(^"Layout/Split")
	var host: Control = tab.get_node(^"%PanelHost")
	assert_lt(host.size.x, split.size.x - 100.0,
		"a shown 150px sidebar must take width from the panel")
	holder.queue_free()


## A tab that authors a panel scenically under %PanelHost has it *adopted*, not
## re-instanced on top — so the slot ends with exactly the one authored child.
func test_baked_panel_child_is_adopted_not_duplicated() -> void:
	var tab: SandboxLiveTab = load(_BASE).instantiate()
	var panel_host: Control = tab.get_node(^"%PanelHost")
	var baked := Control.new()
	baked.name = "BakedPanel"
	panel_host.add_child(baked)

	add_child(tab)  # fires _ready → _mount_panel
	await get_tree().process_frame

	assert_eq(panel_host.get_child_count(), 1, "adopted panel must not be duplicated")
	assert_eq(panel_host.get_child(0), baked, "the authored child must be the mounted panel")
	tab.queue_free()


## An empty %PanelHost stays empty: the legacy `panel_scene` injection path is
## gone (#881), so the base has nothing to instance and must not invent a panel
## or error — an un-baked tab is simply an empty tab (the lint in
## test_sandbox_host_tabs.gd is what catches one).
func test_empty_slot_stays_empty_without_injection() -> void:
	var tab: SandboxLiveTab = load(_BASE).instantiate()
	assert_false("panel_scene" in tab, "the legacy export is gone (#881)")

	add_child(tab)
	await get_tree().process_frame

	var panel_host: Control = tab.get_node(^"%PanelHost")
	assert_eq(panel_host.get_child_count(), 0, "nothing to adopt, nothing instanced")
	tab.queue_free()
