@tool
class_name Admits
extends Resource

## Abstract: which landing copies a node in a band lets through. #1807 owns the
## answer; #1798 gives it its seams. A null [Admits] admits every arrival.


## The admit read (ADR 0083 §2, ADR 0087 §1): asked about each copy arriving at
## [param node], against [param before], the node's terrain before this
## generation's element riders land. True lands it; false absorbs it: the copy
## makes no entry (no damage, no aspect rider), but its element riders land all
## the same. Never asked about a head or a centre copy. Base: lands everything.
func admit(_node: SkillNode, _before: TerrainRead, _arrival: Arrival) -> bool:
	return true
