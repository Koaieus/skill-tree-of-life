@tool
extends Node2D
## One rigid ring of a [CoreHalos] style, drawn ONCE and animated by
## [member Node2D.rotation] instead of by a redraw (#802).
##
## RINGS, ORBIT and COG all animate by rotating rigid geometry about the
## node's own centre — which is exactly what a [CanvasItem] transform is. They
## could not use one before only because [CoreHalos._draw] rendered every
## style into the ONE shared canvas item, so nothing could rotate
## independently. Split onto their own items they are drawn once and then cost
## a float write per frame, whether or not anyone is looking at them; the
## measured 5.74ms COG term (300 blockers, 2000-node board) was pure rebuild.
##
## Owns no geometry of its own — it asks its parent [CoreHalos] to paint it,
## untyped/duck-typed exactly the way core_halos_back.gd borrows the gimbal
## helpers (CoreHalos deliberately declares no `class_name`, matching every
## other leaf in this family).
##
## Instanced by [CoreHalos._rebuild_spin_layers] and never given an `owner`, so
## an editor save can't serialize these into the scene (same discipline as
## SkillNodeVisual's `_validate_property` un-bake).

## Which ring of the style this layer is: RINGS has three at different radii
## and rates, ORBIT and COG one each. Passed straight back to
## [method CoreHalos.paint_spin_layer].
var layer_index: int = 0

## Multiplier on [CoreHalos]' shared spin clock. The parent writes
## `rotation = anim_time * spin_speed * spin_rate` every tick; a per-layer rate
## is what lets RINGS' three rings spin at 1.0 / 1.5 / 2.0 without three
## redraws.
var spin_rate: float = 1.0


func _draw() -> void:
	var halos := get_parent()
	if halos == null or not is_instance_valid(halos):
		return
	halos.paint_spin_layer(self, layer_index)
