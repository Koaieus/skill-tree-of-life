extends SceneTree
## One-off generator for the sandbox host scene (#77). Builds ONLY
## `sandbox_host.tscn` programmatically, so the file is engine-serialized
## (no hand-authored uid-mismatch / field-strip pitfalls — see
## .claude/rules/godot-workflow.md). Run headless:
##
##     godot --headless --script res://tools/gen_sandbox_tabs.gd
##
## It does NOT add nodes to the tree, so the @tool _ready bodies don't fire —
## only the exported config is packed, exactly what the runtime host expects.
##
## TAB SCENES ARE NOT GENERATED AT ALL — every tab is now hand-authored (#250
## live tabs, #260 the last played cards). A live tab is a one-node **inherited
## scene** of `sandbox_live_tab.tscn` (the scenic base with the breadcrumb
## toolbar + %PanelHost slot) that *instances its panel scene inside itself*
## under %PanelHost, overriding tab_title / tab_id / loader_method — never via
## the legacy `panel_scene` export, which `add_child`s the panel at runtime
## instead of shipping it pre-packaged (see
## .claude/rules/sandbox-host.md). Inherited scenes can't be expressed via
## PackedScene.pack, and they hand-author cleanly (path-resolved
## ext_resources, no uid landmines), so to add a tab: copy an existing one
## under `addons/sandbox_host/tabs/` (e.g. `70_bloom_tab.tscn`) and swap the
## values. There is no played-tab generator path left: generating one would
## silently clobber a hand-authored live tab on the next run (the 60_toast
## landmine this retired, #260).

const _DIR := "res://addons/sandbox_host/"

const _HOST := preload("res://addons/sandbox_host/sandbox_host.gd")


func _initialize() -> void:
	_gen_host()
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
