@tool
extends Control
## Live-preview panel for the SkillNode-visuals-v2 component family (#122).
## Every slot is scene-composed in node_visuals_panel.tscn (composite +
## the 6 leaf components), so selecting a child in the scene tree dock and
## tweaking its @export vars gives instant `queue_redraw()` feedback — no
## code in this script builds or wires anything.


## Unlike the spell/vfx/statboard live tabs, this panel isn't driven by an
## inspected resource — every slot is a permanent scene child. No-op that
## exists solely to satisfy SandboxLiveTab.loader_method's contract (see
## test_sandbox_host_tabs.gd::test_tab_scene_exports_resolve).
func noop(_obj: Object) -> void:
	pass
