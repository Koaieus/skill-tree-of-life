class_name PropagationPick
extends RefCounted

## One selected destination of a landing's expansion, as a [PropagationSpread]
## hands it to [method PropagationConfig.mint] (#852). Selection facts only:
## the spread decides these, the mint copies them onto the child verbatim, and
## neither party ever sees the other's arithmetic.
##
## Every field beyond [member node] and [member share] is a fact
## [CycloneSpread] stamps on its children; they are typed fields rather than a
## dictionary so a reader can find every writer with one grep.


## Where the child lands.
var node: SkillNode = null

## The fraction of the progressed damage this arc carries — the child's
## [member CastSpell.arrival_share] IS this number. 1.0 for an ordinary fan.
var share: float = 1.0

## Heading the child arrives on; [Vector2.ZERO] leaves the child's
## [member CastSpell.arrival_bearing] unset (a non-curl spell).
var arrival_bearing: Vector2 = Vector2.ZERO

## +1 / -1 handedness of the turn that produced this pick, 0.0 when the spread
## has no handedness. See [member CastSpell.turn_sign].
var turn_sign: float = 0.0

## True when landing on [member node] closes a simple cycle in the lineage.
## See [member CastSpell.closed_cycle].
var closed_cycle: bool = false

## The predecessor set the arrival records for the closer/backtrack logic;
## see [member CastSpell.came_from].
var came_from: Array[SkillNode] = []

## When non-empty, REPLACES the child's lineage: the ring a closing hop just
## walked, ending at [member node] (see [method CycloneSpread.closed_ring]).
## Empty means the ordinary lineage — the parent's `visited` plus [member node].
var lineage_override: Array[SkillNode] = []


static func to(node_: SkillNode, share_: float = 1.0) -> PropagationPick:
	var p := PropagationPick.new()
	p.node = node_
	p.share = share_
	return p
