@tool
class_name ElementBand
extends Resource

## One band of an [Element]'s terrain stack: a threshold (a multiple of T, or
## the node's cap) and the answers a node in it gives — its go-off, what it
## admits, its travel verb, its decay rate and whether it lights. A new band is
## earned only by a change in kind (`docs/design/elements/go-offs.md`).

## How the band's state travels: ENDS stops at the node (Frozen), CONDUCTS
## carries along edges (Shocked), SPREADS seeps to neighbours (Burning).
enum Travel { NONE, ENDS, CONDUCTS, SPREADS }

## The [member excess_names] key that means "the node's cap k × T" rather than
## a multiple of T (a band's own threshold is ≥ 1, so 0 is free).
const EXCESS_AT_CAP := 0

## The threshold as a multiple of T (≥ 1). Ignored when [member at_cap].
@export_range(1, 100, 1, "or_greater") var threshold_multiple: int = 1
## True: the threshold is the node's cap k × T (k is per node), and
## [member threshold_multiple] is ignored. Only the last band is at the cap.
@export var at_cap: bool = false
## The band's display atom ([code]Kind.ELEMENT[/code]); null falls back to the band below.
@export var identity: Identity = null
## What a node in this band does when it goes off; null until #1799/#1800/#1806.
@export var go_off: GoOff = null
## What a node in this band admits; null admits every arrival (Ice's bands
## hold one [FrozenAdmits]).
@export var admits: Admits = null
@export var travel: Travel = Travel.NONE
## Charge a spell walk spends passing through a node in this band when its
## [member travel] is CONDUCTS (Shocked: 1). Tentative knob; read by the gather.
@export_range(0, 5) var conduct_cost: int = 0
## Terrain decay per world turn while in this band (a knob; read by #1795).
@export_range(0, 100, 1, "or_greater") var decay_per_world_turn: int = 1
## The band is a light source (Burning): every viewer sees a disc of
## [method DiscGoOff.disc_radius] over the node's excess ([VisionSystem]).
@export var light: bool = false
## The band burns its holder each world turn: TRUE damage of this × the excess
## (count − T) on an allocated node ([method CombatWorld.burn_terrain]). 0 burns
## nothing. A knob, tentative (pass reading of the owner's "1 per stack").
@export_range(0.0, 10.0) var burn_per_excess: float = 0.0
## Display names on the excess (#1796): threshold → name, the threshold read as
## a band's is — a multiple of T, or the node's cap when the key is
## [constant EXCESS_AT_CAP]. A node shown in this band reads the name of the
## highest threshold its count passes (the cap outranks a multiple it ties);
## below them all, the band's own [member identity] noun. Names only: the
## colour and icon stay the band's. Fire's Burning: Blaze past 2 × T, Inferno
## past the cap. Empty on every other band. Tentative (pass pick).
@export var excess_names: Dictionary[int, String] = {}
