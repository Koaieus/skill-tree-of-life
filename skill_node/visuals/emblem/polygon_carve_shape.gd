@tool
class_name PolygonCarveShape
extends CarveShape
## A regular N-gon carve — the analytic "gem facet" bowl dent InnerDisk already
## renders (`sn_bowl_drop`, batch-friendly, no per-instance texture). [member
## squish_x] anisotropically narrows the X extent — a uniform axis scale on
## the same regular polygon, not a new shape family — so e.g. DEX's "diamond
## squished from the sides" is just `PolygonCarveShape(sides=4, squish_x<1.0)`.

##
## The geometry lives HERE rather than on [CarveShape] on purpose (#285): only
## the polygon path reads it (`sn_bowl_drop`), while [GemCarveShape] bakes a
## fixed silhouette and [TextureCarveShape] its own art — a base-class field
## would be one they'd have to document as ignored.

## Regular-polygon side count (3 = triangle … 12 = dodecagon).
@export_range(3, 16, 1) var sides: int = 3

## 1.0 = regular; < 1.0 narrows the shape's X extent.
@export_range(0.3, 1.0, 0.01) var squish_x: float = 1.0

## Circumradius relative to the disk radius. At 1.0 the polygon's vertices sit
## exactly on the disk's circle.
@export_range(0.4, 1.15, 0.01) var radius: float = 0.75

## Max depth of this shape's bowl dent, overriding [member InnerDisk.well_depth].
## NEGATIVE = inherit the disk's own depth — depth is primarily a uniform "how
## carved does this game look" dial, and a shape only opts out when its own read
## needs to (a 12-gon at a triangle's depth reads shallower). A deliberate 0.0
## stays meaningful ("no dent") and distinct from unset.
##
## The sentinel is resolved on the CPU, in [member InnerDisk.effective_well_depth]
## — it must never reach the shader, whose uniform is `hint_range(0.0, 1.0)` and
## would clamp a negative to 0.0, silently flattening every inheriting shape.
@export_range(-1.0, 1.0, 0.01) var well_depth: float = -1.0
