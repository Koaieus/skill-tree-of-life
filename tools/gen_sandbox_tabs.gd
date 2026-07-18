extends SceneTree
## One-off generator for the sandbox host scenes (#77). Builds the host scene +
## the *played* launch-card tabs programmatically and saves them, so the .tscn
## files are engine-serialized (no hand-authored uid-mismatch / field-strip
## pitfalls — see .claude/rules/godot-workflow.md). Re-run after changing the
## played-tab roster:
##
##     godot --headless --script res://tools/gen_sandbox_tabs.gd
##
## It does NOT add nodes to the tree, so the @tool _ready bodies (which build the
## panel / card) don't fire — only the exported config is packed, exactly what
## the runtime host expects to instance.
##
## Live-edit tabs are NOT generated here anymore (#250). A live tab is now a
## one-node **inherited scene** of `sandbox_live_tab.tscn` (the scenic base with
## the breadcrumb toolbar + %PanelHost slot) overriding only tab_title / tab_id /
## panel_scene / loader_method. Inherited scenes can't be expressed via
## PackedScene.pack, and they hand-author cleanly (path-resolved ext_resources,
## no uid landmines), so to add a live tab: copy an existing one under
## `addons/sandbox_host/tabs/` (e.g. `18_fan_trace_tab.tscn`) and swap the values.

const _DIR := "res://addons/sandbox_host/"
const _TABS := "res://addons/sandbox_host/tabs/"

const _PLAYED := preload("res://addons/sandbox_host/sandbox_played_tab.gd")
const _HOST := preload("res://addons/sandbox_host/sandbox_host.gd")


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_TABS))

	_gen_host()

	# Played tabs — launch cards.
	_gen_played("40_allocation_tab", "Allocation VFX",
		"res://scenes/dev/allocation_vfx_showcase.tscn",
		"Allocation / deallocation / death VFX on a 3×3 grid, driven by the real "
		+ "AllocationSystem + BattleSystem + VFX layers on a self-resetting loop.")
	_gen_played("50_loot_tab", "Loot",
		"res://scenes/dev/loot_showcase.tscn",
		"Kill → XP floater on the killer + a SkillDust relic blooming on the "
		+ "victim's former core, driven by the real LootSystem on a loop.")
	_gen_played("60_toast_tab", "Toasts",
		"res://scenes/dev/toast_showcase.tscn",
		"Every FloaterStyle on demand — one +1/+3 button row per variant, driven "
		+ "by the real FloaterToasterManager. The debug vehicle for the "
		+ "strikethrough toast (#84).")

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
