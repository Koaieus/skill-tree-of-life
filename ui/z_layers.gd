## Single source of truth for canvas z-index bands used across the graph + VFX stack.
## Load with:
##   const ZLayers = preload("res://ui/z_layers.gd")
##
## Bands (bottom → top):
##   AURA        -100    absolute — owned-node territory wash, behind everything on the graph
##   EDGE        -10     absolute — edges always draw below graph nodes
##   GRAPH_DEFAULT  0     relative — scene-tree order governs draw order within the band
##   CORE_MOVE    100     relative — core ghost/badge above graph siblings during a move
##   FOG         1000     absolute — FogOverlay shader covers all graph content
##   SENSED      1001     absolute — sensed/visible nodes punch through the fog
##   SPELL_VFX   2000     absolute — allocation ring + floaters, above fog + sensed
##   PROJECTILE  3000     absolute — attack projectiles, above spell VFX
##   UI          4096     absolute — pause overlay; engine ceiling (CanvasItem range ±4096)
##
## .tscn files that can't reference these constants use the raw integer; the
## canonical value lives here. Nodes whose script already sets z_index in code
## (e.g. AllocationVFX._ready) need not repeat it in the scene file.

## A SECOND, INDEPENDENT AXIS: `CanvasLayer.layer`. Every band above is
## `z_index`, which only orders CanvasItems *within* one canvas layer — a
## CanvasLayer always wins over any z_index below it, and a nested CanvasLayer's
## `layer` is absolute, not relative to its parent. The stack, bottom → top:
##
##   SpaceBackground   -100   ui/space_background/space_background.tscn
##   the world            0   graph, fog, VFX — the root viewport's own canvas
##   ArmedModeGlow        1   #412 armed-mode border glow, frames the play area
##   UI (HudRoot)         2   scenes/game_root.tscn — HUD panels draw over the glow
##   AnnouncementLayer   95   ui/announcement_layer/
##   RunEndOverlay      100   ui/run_end_overlay/run_end_overlay.tscn
##
## `default_game_env.tres` sets `background_canvas_max_layer = 100`, so
## everything through RunEndOverlay reaches the bloom pass; a layer above 100
## would silently stop glowing. These live in their own `.tscn` files rather
## than as constants here because Godot can't reference a script const from a
## scene property — this comment is the index, the scenes are the source.

const AURA: int = -100
const EDGE: int = -10
const GRAPH_DEFAULT: int = 0
const CORE_MOVE: int = 100
const FOG: int = 1000
const SENSED: int = 1001
const SPELL_VFX: int = 2000
const PROJECTILE: int = 3000
const UI: int = 4096
