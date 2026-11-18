class_name GoOffSource
extends RefCounted

## A second store a head carries into the gather beside its target node's: a
## blade vertex's copied terrain ([method HitInstance.go_off_source]).
## [HitGather] reads [member read]'s bands at the head's own node and fires
## each band's [GoOff] from there, spending through [member spend], never off
## the node's ints. A value the head hands once per gather; nothing here names
## the store's type.

## What holds the copy (a blade's [BladeState]), and which slot of it.
var holder: Object = null
var index: int = -1
## The copy's four ints, as a [TerrainRead] of a node would hold them. An
## inert copy answers no band, so nothing goes off from it.
var read: TerrainRead = null
## `(element: Element, stacks: int) -> void`: takes [param stacks] off the
## copy's store of [param element].
var spend: Callable


func _init(at_holder: Object = null, at_index: int = -1, at_read: TerrainRead = null,
		at_spend: Callable = Callable()) -> void:
	holder = at_holder
	index = at_index
	read = at_read
	spend = at_spend
