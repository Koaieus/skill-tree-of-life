@tool
class_name SpaceBackground
extends CanvasLayer

## Procedural deep-space backdrop: a flat dark base plus a nebula tint and three
## star layers, each hosted in a [Parallax2D] so they scroll at different rates
## as the camera pans — subtle multi-depth parallax. Sits on a negative
## CanvasLayer (`layer = -100`) so it renders behind all world content; the HUD
## lives on a positive CanvasLayer and stays on top.
##
## Everything designable lives in the scene: the per-layer look is on each
## Parallax2D child's ShaderMaterial (starfield/nebula .gdshader), the depth on
## its `scroll_scale`. Purely cosmetic — remove this node and gameplay is
## unchanged, which is why it needs no injected dependencies (Parallax2D reads
## the active Camera2D itself).

## Master toggle so a showcase / embed can drop the backdrop without deleting it.
@export var enabled: bool = true:
	set(value):
		enabled = value
		visible = value
