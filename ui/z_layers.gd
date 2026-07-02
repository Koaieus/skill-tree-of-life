## Single source of truth for canvas z-index bands used across the graph + VFX stack.
## Load with:
##   const ZLayers = preload("res://ui/z_layers.gd")
##
## Bands (bottom → top):
##   AURA        -100    absolute — owned-node territory wash, behind everything on the graph
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

const AURA: int = -100
const GRAPH_DEFAULT: int = 0
const CORE_MOVE: int = 100
const FOG: int = 1000
const SENSED: int = 1001
const SPELL_VFX: int = 2000
const PROJECTILE: int = 3000
const UI: int = 4096
