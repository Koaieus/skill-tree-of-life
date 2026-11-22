class_name GoOffSource
extends RefCounted

## The incoming party a head carries into the gather beside its target node
## (ADR 0098): a blade vertex's copied terrain ([method HitInstance.go_off_source])
## or a cast's shape ([method shape]). [HitGather] fires each element's [GoOff]
## once at the head's own node with the node's read AND this party; the go-off
## reads the party's size off it (a copy's [member read], a shape's
## [member points]) and bills the party's own solo cost as
## [member GoOffResult.incoming_cost], which the gather takes through
## [member spend], never off the node's ints. A shape has no read and no
## payer: it reaches, pays nothing and has no effect of its own.

## What holds the copy (a blade's [BladeState]), and which slot of it.
var holder: Object = null
var index: int = -1
## A copy's four ints, as a [TerrainRead] of a node would hold them; null for
## a shape. An inert copy answers no band, so it contributes nothing.
var read: TerrainRead = null
## `(element: Element, stacks: int) -> void`: takes [param stacks] off the
## party's store of [param element]; invalid for a shape (no payer).
var spend: Callable
## A shape's element and points ([member HitInstance.cast_shape]); null / 0 for a copy.
var element: Element = null
var points: int = 0


func _init(at_holder: Object = null, at_index: int = -1, at_read: TerrainRead = null,
		at_spend: Callable = Callable()) -> void:
	holder = at_holder
	index = at_index
	read = at_read
	spend = at_spend


## A cast's shape of [param e] × [param points]: no read, no payer.
static func shape(e: Element, at_points: int) -> GoOffSource:
	var out := GoOffSource.new()
	out.element = e
	out.points = at_points
	return out


func is_shape() -> bool:
	return read == null and element != null


## Whether the party has a payer: a copy does, a shape does not.
func pays() -> bool:
	return spend.is_valid()

