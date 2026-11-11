@tool
class_name GoOff
extends Resource

## What a primed node does when a hit sets it off: the element's reach (#1798
## gives the contract; #1799 the disc, #1806 the edge). [HitGather] calls
## [method fire] at a node's read, handing it the node's terrain after the
## generation's element riders landed as sums (never the pre-beat snapshot;
## ADR 0083 §1, §5) and the hit's load (the head's; 0 on a copy). The gather
## commits the spend it returns as returned, and makes entries (each reached
## node, plus the centre copy) only when the reach holds a node.
##
## The base is the element law (ADR 0081 §1): spend 1 per other node
## [method _reach] returns, the centre copy uncounted, so reaching no other node
## spends 0 and does not go off; a spend may dig under T. Every reach at depth
## 1, at [member share], own damage 0. A subclass overrides [method _reach] for
## its shape, or [method fire] for another law (#1799's go-off zero).

## The share of this go-off's copies, its centre copy included: damage × s,
## riders ceil(r × s). Tentative knob (#1798); 1 = the whole hit (ADR 0086 §1).
@export_range(0.0, 1.0, 0.05) var share := 1.0
## Whether the go-off lands one more copy on the node it goes off from (the
## whole hit, ADR 0086 §1). Tentative knob; #1799's disc sets it false.
@export var lands_on_own_node := true


func fire(node: SkillNode, read: TerrainRead, hit_load: int) -> GoOffResult:
	var out := GoOffResult.new()
	out.share = share
	for reach in _reach(node, read, hit_load):
		if reach == null or reach.node == null or reach.node == node or out.cost.has(reach.node):
			continue
		out.reached.append(reach)
		out.cost[reach.node] = 1
	return out


## The shape: the other nodes this go-off reaches from [param node], by shape
## alone, allocated or not (ADR 0084 §7). Base: none.
func _reach(_node: SkillNode, _read: TerrainRead, _hit_load: int) -> Array[GoOffResult.Reach]:
	var out: Array[GoOffResult.Reach] = []
	return out
