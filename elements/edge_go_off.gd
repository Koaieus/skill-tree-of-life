@tool
class_name EdgeGoOff
extends GoOff

## The edge [GoOff] (Lightning's Shocked): a node that goes off arcs to every
## node within L hops over the whole graph, the centre excluded, allocated or
## not (ADR 0084 §7), L read off the node's post-land Charge on the ladder
## `count > L^exp × T` ([method level_of]). Each reached node costs 1 and, on
## the transfer default, takes the spent stack ([member GoOffResult.transfer]);
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
## Where each spent stack lands: on the node it reached (the owner's default:
## an arc moves its Charge, ADR 0084 §7) or nowhere.
@export_enum("Reached node", "Void") var spent_charge_goes_to: int = SpentChargeGoesTo.REACHED_NODE


## The arc's level off [param read]: the highest L ≤ [member max_level] with
## Charge > L^[member ladder_exponent] × T; 0 when Charge ≤ T (inert).
func level_of(_read: TerrainRead) -> int:
	return 0


func fire(node: SkillNode, read: TerrainRead) -> GoOffResult:
	return fire_level_in(null, node, read, 0)


## The arc at the read's own level plus [param added] (ADR 0084 §3, §4): one
## go-off reaching every node within M + added hops, paying the node's solo
## cost (1 per node within its own level M, each also its transfer).
func fire_level_in(_world: CombatWorld, _node: SkillNode, _read: TerrainRead, _added: int) -> GoOffResult:
	var out := GoOffResult.new()
	out.share = share
	return out
