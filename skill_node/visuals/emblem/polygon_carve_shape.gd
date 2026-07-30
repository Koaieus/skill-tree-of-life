@tool
class_name PolygonCarveShape
extends CarveShape
## A regular N-gon carve — the analytic "gem facet" bowl dent InnerDisk already
## renders (`sn_bowl_drop`, batch-friendly, no per-instance texture). [member
## squish_x] anisotropically narrows the X extent — a uniform axis scale on
## the same regular polygon, not a new shape family — so e.g. DEX's "diamond
## squished from the sides" is just `PolygonCarveShape(sides=4, squish_x<1.0)`.

## Regular-polygon side count (3 = triangle … 12 = dodecagon).
@export_range(3, 16, 1) var sides: int = 3

## 1.0 = regular; < 1.0 narrows the shape's X extent.
@export_range(0.3, 1.0, 0.01) var squish_x: float = 1.0
