extends GutTest
## Lints the auto-discovered sandbox host tab scenes (#77): every tab .tscn must
## load, root as a SandboxTab, with its exported config resolved non-null.
## Hand/generator-authored .tscn can silently null an @export (uid mismatch /
## field strip — see .claude/rules/godot-workflow.md); this is the guard the
## rule prescribes ("load the preset and assert every field is non-null").

const _TABS_DIR := "res://addons/sandbox_host/tabs/"

var _params := _tab_files()


static func _tab_files() -> Array:
	var out: Array = []
	var dir := DirAccess.open(_TABS_DIR)
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".tscn"):
				out.append(f)
	out.sort()
	return out


func test_tabs_dir_is_non_empty() -> void:
	assert_gt(_tab_files().size(), 0, "expected tab scenes under %s" % _TABS_DIR)


func test_tab_scene_exports_resolve(p = use_parameters(_params)) -> void:
	var scene: PackedScene = load(_TABS_DIR + p)
	assert_not_null(scene, "%s failed to load" % p)
	var tab = scene.instantiate()
	assert_true(tab is SandboxTab, "%s root must extend SandboxTab" % p)
	assert_ne(tab.get_tab_title(), "", "%s has empty tab_title" % p)

	if tab.get_mode() == SandboxTab.Mode.LIVE_EDIT:
		assert_ne(tab.tab_id, &"", "%s (live) has empty tab_id" % p)
		# Baked tabs (.claude/rules/sandbox-host.md) instance their panel inside
		# %PanelHost and carry no panel_scene; legacy tabs still inject via the export.
		var panel_host: Node = tab.get_node_or_null(^"%PanelHost")
		var is_baked := panel_host != null and panel_host.get_child_count() > 0
		assert_true(tab.panel_scene != null or is_baked,
			"%s (live) has null panel_scene and no baked %%PanelHost child" % p)
		assert_ne(tab.loader_method, &"", "%s (live) has empty loader_method" % p)
	else:
		assert_ne(tab.scene_path, "", "%s (played) has empty scene_path" % p)
		assert_true(ResourceLoader.exists(tab.scene_path),
			"%s (played) scene_path missing on disk: %s" % [p, tab.scene_path])

	tab.free()


func test_host_scene_loads() -> void:
	var host_scene: PackedScene = load("res://addons/sandbox_host/sandbox_host.tscn")
	assert_not_null(host_scene, "sandbox_host.tscn failed to load")
	var host = host_scene.instantiate()
	assert_true(host is SandboxHost, "host root must be a SandboxHost")
	assert_not_null(host.get_node_or_null("Tabs"), "host must carry its Tabs TabContainer")
	host.free()
