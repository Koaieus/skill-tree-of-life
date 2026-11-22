class_name GoOffResult
extends RefCounted

## What a [GoOff] answers ([method GoOff.fire]): the nodes it reached, the
## spend, where spent stacks go, the share and its own damage. [HitGather]
## commits the spend as returned and never recounts it from the reach.


## One node a go-off reached: its hop depth (1 unless the go-off names more)
## and, at depth 2 and up, the ring nodes it hangs behind: the reached nodes at
## depth − 1 it neighbours, a set (the hop seat, #1798, tentative). A go-off
## fired at generation g lands a depth-d node at g + d; its cost and transfer
## commit at g + d − 1's read, and it drops there when every ring node ended
## its paths or dropped ([HitGather]). #1806 fills both from its BFS.
class Reach:
	extends RefCounted
	var node: SkillNode = null
	var depth: int = 1
	var ring: Array[SkillNode] = []

	func _init(at: SkillNode = null, at_depth: int = 1) -> void:
		node = at
		depth = at_depth


var reached: Array[Reach] = []
## `SkillNode -> int`: the spend per reached node. Only a reached node's cost
## commits (spend follows landings, ADR 0093 §5).
var cost: Dictionary = {}
## A spend that names no node, committed all the same at the go-off's own
## read: the floor a primed node voids each time it goes off
## ([member GoOff.void_floor]).
var nodeless_cost: int = 0
## `SkillNode -> int`: the element's terrain each reached node takes (Fire's
## Heat, Lightning's Charge), on the element's "Reached node" default. Lands
## whether or not the payer could cover its cost; never capped by the
## once-per-node set.
var transfer: Dictionary = {}
var share: float = 1.0
var own_damage: float = 0.0
## What the go-off's [BlastMark] draws: its reach in px and its power, filled
## by a go-off that has them (a disc's radius and power at the read; an edge
## go-off's hop level as power, with no px reach); 0 when it does not.
var reach: float = 0.0
var power: int = 0


## The whole spend: every reached node's cost, plus the nodeless one.
func spend() -> int:
	var total := nodeless_cost
	for r in reached:
		if r != null:
			total += int(cost.get(r.node, 0))
	return total


## The spend that commits at the go-off's own read: the nodeless cost and each
## depth-1 node's. A deeper node's commits later, and only when its entry is
## not dropped (spend follows landings, ADR 0093 §5).
func spend_at_read() -> int:
	var total := nodeless_cost
	for r in reached:
		if r != null and r.depth <= 1:
			total += int(cost.get(r.node, 0))
	return total
