extends SceneTree
## One-off generator for the sandbox host scenes (#77). Builds the host scene +
## each tab scene programmatically and saves them, so the .tscn files are
## engine-serialized (no hand-authored uid-mismatch / field-strip pitfalls — see
## .claude/rules/godot-workflow.md). Re-run after changing the tab roster:
##
##     godot --headless --script res://tools/gen_sandbox_tabs.gd
##
## It does NOT add nodes to the tree, so the @tool _ready bodies (which build the
## panel / card) don't fire — only the exported config is packed, exactly what
## the runtime host expects to instance.

const _DIR := "res://addons/sandbox_host/"
const _TABS := "res://addons/sandbox_host/tabs/"

const _LIVE := preload("res://addons/sandbox_host/sandbox_live_tab.gd")
const _PLAYED := preload("res://addons/sandbox_host/sandbox_played_tab.gd")
const _HOST := preload("res://addons/sandbox_host/sandbox_host.gd")


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_TABS))

	_gen_host()

	# Live-edit tabs — numeric prefixes fix the tab order.
	_gen_live("10_spell_tab", "Spell", &"spell",
		"res://addons/spell_playground/playground_panel.tscn", &"load_spell")
	_gen_live("20_vfx_tab", "VFX", &"vfx",
		"res://addons/vfx_playground/playground_panel.tscn", &"load_coordinator")
	_gen_live("30_statboard_tab", "StatBoard", &"statboard",
		"res://addons/stat_board_visualizer/stat_board_graph.tscn", &"load_board")

	# Played tabs — launch cards.
	_gen_played("40_allocation_tab", "Allocation VFX",
		"res://scenes/dev/allocation_vfx_showcase.tscn",
		"Allocation / deallocation / death VFX on a 3×3 grid, driven by the real "
		+ "AllocationSystem + BattleSystem + VFX layers on a self-resetting loop.")
	_gen_played("50_loot_tab", "Loot",
		"res://scenes/dev/loot_showcase.tscn",
		"Kill → XP floater on the killer + a SkillDust relic blooming on the "
		+ "victim's former core, driven by the real LootSystem on a loop.")

	quit()


func _gen_host() -> void:
	var root := Control.new()
	root.set_script(_HOST)
	root.name = "SandboxHost"
	var tabs := TabContainer.new()
	tabs.name = "Tabs"
	root.add_child(tabs)
	tabs.owner = root
	tabs.set_anchors_preset(Control.PRESET_FULL_RECT)
	_save(root, _DIR + "sandbox_host.tscn")


func _gen_live(file: String, title: String, id: StringName, panel: String, loader: StringName) -> void:
	var tab := MarginContainer.new()
	tab.set_script(_LIVE)
	tab.name = title
	tab.tab_title = title
	tab.tab_id = id
	tab.panel_scene = load(panel)
	tab.loader_method = loader
	_save(tab, _TABS + file + ".tscn")


func _gen_played(file: String, title: String, scene: String, description: String) -> void:
	var tab := MarginContainer.new()
	tab.set_script(_PLAYED)
	tab.name = title
	tab.tab_title = title
	tab.scene_path = scene
	tab.description = description
	_save(tab, _TABS + file + ".tscn")


func _save(node: Node, path: String) -> void:
	var packed := PackedScene.new()
	var err := packed.pack(node)
	if err != OK:
		push_error("pack failed for %s: %s" % [path, err])
		return
	err = ResourceSaver.save(packed, path)
	if err != OK:
		push_error("save failed for %s: %s" % [path, err])
		return
	print("wrote ", path)
