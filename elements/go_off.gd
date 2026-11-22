@tool
class_name GoOff
extends Resource

## What a primed node does when a hit sets it off: the element's reach (#1798
## gives the contract; #1799 the disc, #1806 the edge). [HitGather] calls
## [method fire_in] (which defaults to [method fire]) at a node's read, handing it the node's terrain after the
## generation's element riders landed as sums (never the pre-beat snapshot;
## ADR 0083 §1, §5). The gather
## commits the spend it returns as returned, and makes entries (each reached
## node, plus the centre copy) only when the reach holds a node.
##
## Cost and effect (ADR 0098): every primed party — the node, and an incoming
## [GoOffSource] copy — voids [member void_floor] and pays 1 more per node
## inside its own reach, measured from the hit node (the node's
## [member GoOffResult.cost] + [member GoOffResult.nodeless_cost], the copy's
## [member GoOffResult.incoming_cost]); a spend may dig under T and stops at 0.
## Reaching nobody makes no entry yet still voids the floor while
## [member floor_when_unreached] holds. The effect is separate and never
## funded by the cost: the element's (the base has none; Fire's disc and
## Lightning's arc land +1 on every node the go-off reaches by default). The
## gather calls [method fire_with]; every reach at depth 1, at
## [member share], own damage 0. A subclass overrides [method _reach] for its
## shape, [method fire] for another law, or [method fire_with] to size the
## reach by both parties.

## The share of this go-off's copies, its centre copy included: damage × s,
## riders ceil(r × s). Tentative knob (#1798); 1 = the whole hit (ADR 0086 §1).
@export_range(0.0, 1.0, 0.05) var share := 1.0
## Whether the go-off lands one more copy on the node it goes off from (the
## whole hit, ADR 0086 §1). Tentative knob; #1799's disc sets it false.
@export var lands_on_own_node := true
## The stacks a primed node voids each time it goes off, on top of the 1 per
## reached node (ADR 0097 §2, §4): what lets a board settle. Tentative knob,
## easy to change. Editor feedback: the sandbox host's blast tab.
@export_range(0, 5) var void_floor := 1
## Whether a go-off that reaches nobody still voids [member void_floor] (ADR
## 0097 §5; only Fire's disc can reach nobody). Tentative knob.
@export var floor_when_unreached := true


func fire(node: SkillNode, read: TerrainRead) -> GoOffResult:
	var out := GoOffResult.new()
	out.share = share
	for reach in _reach(node, read):
		if reach == null or reach.node == null or reach.node == node or out.cost.has(reach.node):
			continue
		out.reached.append(reach)
		out.cost[reach.node] = 1
	out.nodeless_cost = floor_for(not out.reached.is_empty())
	return out


## The floor a primed node going off voids: [member void_floor], or 0 when it
## [param reached_any] nobody and [member floor_when_unreached] is off.
func floor_for(reached_any: bool) -> int:
	return void_floor if reached_any or floor_when_unreached else 0


## [method fire] on [param world]'s store: the call [HitGather] makes, handing
## the world it gathers on (a cast's shadow included). Base: [method fire],
## which reads nothing off a store; a go-off that reads one (#1799's disc)
## overrides this and has [method fire] read the live world.
func fire_in(_world: CombatWorld, node: SkillNode, read: TerrainRead) -> GoOffResult:
	return fire(node, read)


## The one go-off at [param node] with its two parties (ADR 0098): the node's
## [param read] (null when the node is not primed in this element, or muted)
## and the incoming [param source] (null when none contributes). Base: the
## reach by shape alone, off the node's read or else the source's; the node
## pays only when primed, a source with a payer pays its own floor plus 1 per
## node reached; no effect. [method fire_in] when there is no source.
func fire_with(world: CombatWorld, node: SkillNode, read: TerrainRead, source: GoOffSource) -> GoOffResult:
	if source == null:
		return fire_in(world, node, read)
	var out := fire_in(world, node, read if read != null else source.read)
	if out == null:
		return out
	if source.pays() and source.read != null:
		for r in out.reached:
			out.incoming_at[r.node] = 1
		out.incoming_cost = floor_for(not out.reached.is_empty()) + out.incoming_at.size()
	if read == null:
		out.cost.clear()
		out.nodeless_cost = 0
	return out


## The shape: the other nodes this go-off reaches from [param node], by shape
## alone, allocated or not (ADR 0084 §7). Base: none.
func _reach(_node: SkillNode, _read: TerrainRead) -> Array[GoOffResult.Reach]:
	var out: Array[GoOffResult.Reach] = []
	return out
