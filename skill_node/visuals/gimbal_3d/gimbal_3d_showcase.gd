@tool
extends Control
## Live 3D gimbal-halo showcase (#239): the three boss-tier looks — UNIFORM_GLOW,
## HOLO_GLASS, SOLID_GLYPH — side by side in one real 3D [SubViewport] with a
## glow [Environment]. No inspected resource; noop satisfies the SandboxLiveTab
## loader contract, same as node_visuals_panel.gd.


func noop(_obj: Object) -> void:
	pass
