@tool
class_name EdgeGoOff
extends GoOff

## The edge [GoOff] (Lightning's Shocked): a node that goes off arcs to every
## node within L hops over the whole graph, the centre excluded, allocated or
## not (ADR 0084 §7), L read off the node's post-land Charge on the ladder
## `count > L^exp × T` ([method level_of]). The node voids
## [member GoOff.void_floor] and pays 1 per reached node within its own level;
## on the default each of those takes +1 Charge ([member GoOffResult.transfer]);
## a node at hop depth d ≥ 2 names the depth − 1 nodes it hangs behind
## ([member GoOffResult.Reach.ring]). No own damage. The gather owns the rest
## (chains, the once-per-node set, the generations, the centre landing).

enum SpentChargeGoesTo { REACHED_NODE, VOID }

## The ladder's exponent: level L at count > L^exp × T (the owner's L²).
## Tentative knob. Editor feedback: the sandbox host's blast tab.
@export_range(1, 4) var ladder_exponent := 2
## A ceiling on the level read from the node's own count (a level a caller
## adds is the caller's). Tentative knob; the cap k × T already bounds it.
@export_range(1, 6) var max_level := 3
## Where each per-reached stack goes: +1 Charge on the node it reached (the
## owner's default: a discharge is charged, ADR 0097 §3) or nowhere.
@export_enum("Reached node", "Void") var spent_charge_goes_to: int = SpentChargeGoesTo.REACHED_NODE


## The arc's level off [param read]: the highest L ≤ [member max_level] with
## Charge > L^[member ladder_exponent] × T; 0 when Charge ≤ T (inert). A
## T of 0 reads every stack as past it, capped by [member max_level].
func level_of(read: TerrainRead) -> int:
	if read == null or read.charge <= read.threshold:
		return 0
	var level := 1
	while level < max_level and read.charge > _power(level + 1) * read.threshold:
		level += 1
	return level


## The level a cast's Lightning shape of [param points] buys (ADR 0084 §1):
## level N costs 1 + 2 + … + N, so the largest N with N(N + 1)/2 ≤ points
## (1 / 3 / 6 / 10 points → 1 / 2 / 3 / 4). Pure; no knob (the owner's rule).
static func level_for_points(points: int) -> int:
	var level := 0
	while (level + 1) * (level + 2) <= 2 * points:
		level += 1
	return level


## [param base] ^ [member ladder_exponent], in integers.
func _power(base: int) -> int:
	var out := 1
	for _i in ladder_exponent:
		out *= base
	return out


func fire(node: SkillNode, read: TerrainRead) -> GoOffResult:
	return fire_level_in(null, node, read, 0)


## The arc at the read's own level M plus [param added] (ADR 0084 §3, §4): one
## go-off reaching every node within M + added hops of [param node] (never
## [code]read.node[/code]: a blade source's read names none), paying the
## node's solo cost: [member GoOff.void_floor] nodeless plus 1 per node within
## M hops, each its transfer on the default. M = 0 with an added level is a
## shape alone: it reaches, pays nothing. The reach is the global mirror's one BFS ([method GraphMirror.nodes_within]).
## [member GoOffResult.power] names M + added, the hops its [BlastMark] draws.
func fire_level_in(_world: CombatWorld, node: SkillNode, read: TerrainRead, added: int) -> GoOffResult:
	var out := GoOffResult.new()
	out.share = share
	var own := level_of(read)
	var level := own + maxi(added, 0)
	if node == null or level <= 0:
		return out
	var graph := node.get_graph()
	if graph == null or graph.navigator == null:
		return out
	out.power = level
	var mirror: GraphMirror = graph.navigator
	var depth := mirror.nodes_within(node, level)
	var by_depth: Array = []
	for n: SkillNode in depth:
		if n != null and n != node:
			by_depth.append(n)
	# Ties break on stable_id, the same on host and peer (an instance id is
	# not): the reach order is the copies' landing order.
	by_depth.sort_custom(func(a: SkillNode, b: SkillNode) -> bool:
		return depth[a] < depth[b] if depth[a] != depth[b] else a.stable_id < b.stable_id)
	for n: SkillNode in by_depth:
		var d: int = depth[n]
		var reach := GoOffResult.Reach.new(n, d)
		if d >= 2:
			for nb in mirror.neighbours_of(n):
				if depth.get(nb, -1) == d - 1:
					reach.ring.append(nb)
		out.reached.append(reach)
		if d <= own:
			out.cost[n] = 1
			if spent_charge_goes_to == SpentChargeGoesTo.REACHED_NODE:
				out.transfer[n] = 1
	if own > 0:
		out.nodeless_cost = floor_for(not out.reached.is_empty())
	return out
