class_name TerrainRead
extends RefCounted

## One node's terrain ints as [HitGather] read them at one step of stage one:
## what [method Admits.admit] (before the generation's element riders) and
## [method GoOff.fire] (after them) are handed. A value: later writes never
## move it.

var node: SkillNode = null
var t: int = 0
var charge: int = 0
var threshold: int = 0
var cap: int = 0


static func of(slice: NodeCombat, at: SkillNode) -> TerrainRead:
	var read := TerrainRead.new()
	read.node = at
	if slice != null:
		read.t = slice.terrain_t()
		read.charge = slice.charge()
		read.threshold = slice.terrain_threshold()
		read.cap = slice.terrain_cap()
	return read


## [param element]'s stack count in this read ([method Terrain.count_of]'s rule).
func count(element: Element) -> int:
	match Terrain.axis_of(element):
		Terrain.Axis.HEAT:
			return maxi(t, 0)
		Terrain.Axis.COLD:
			return maxi(-t, 0)
		Terrain.Axis.CHARGE:
			return charge
	return 0


## The band [param element] sits in at this read, or null.
func band(element: Element) -> ElementBand:
	return Terrain.band_of(element, count(element), threshold, cap)
