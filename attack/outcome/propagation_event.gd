class_name PropagationEvent
extends RefCounted

## One beat in a spell's propagation, as the [SpellResolver] emits it. The
## VFX layer ([MagicBounceCoordinator]) walks a [member AttackOutcome.timeline]
## of these — grouped by [member beat] — instead of re-deriving wave structure
## from [member AttackOutcome.hits]. See [code]docs/domain/spell-propagation.md[/code]
## ("The outcome → VFX seam").
##
## The timeline is **additive** over [member AttackOutcome.hits]: an event's
## [member hits] are *shared references* into that same flat list (empty
## for [constant Verb.CANCEL] / zero-damage landings), never copies.

## How the probe arrives at [member target] — the a/b/e/d movement vocabulary.
## There is deliberately no HIT verb: "hit the node" (c) is the arrival phase
## every non-CANCEL event performs, handled by the visual's `_on_arrival()`.
enum Verb {
	JUMP,       ## a — the seed: lands on the target ignoring edges.
	EDGE,       ## b — stepped across one edge from the predecessor.
	SELF_LOOP,  ## e — left and returned via a self-loop edge (target == predecessor).
	CANCEL,     ## d — an IncidentReducer fizzled the spell here; dissipate in place.
}

## Which wave this event belongs to. Equals the landed [CastSpell.hop_index]
## (which stays lockstep with the resolver's wave index). Drives VFX stagger.
var beat: int = 0

## How the probe moved to get here — stamped by the resolver at emission,
## because it can't be recovered from geometry (a self-loop's origin == target).
var verb: Verb = Verb.EDGE

## The node the probe travels FROM (the predecessor node, or the cast-from
## source for the seed). VFX spawns the projectile here.
var origin: SkillNode = null

## The node the probe lands on.
var target: SkillNode = null

## Graph predecessor (the node this probe stepped from). Null at the seed.
## A *node* ref this pass; the event→event fork-tree link is deferred to the
## authoring-dock work.
var predecessor: SkillNode = null

## Every predecessor that converged on this landing — one entry per incident
## the [IncidentReducer] folded together, in incident order. [member predecessor]
## stays the single canonical choice ("where the merged payload came from",
## VFX origin) so nothing that reads it breaks; this is the full set beside it
## (#542, closing the "only one inbound projectile is ever drawn" gap). A
## single-incident landing — the overwhelming majority — carries exactly one
## entry, so [code]predecessors.size() > 1[/code] is what a VFX reader gates
## multi-bolt rendering on ([MagicBounceCoordinator]). Size matches
## [member CastSpell.incident_count] for the landing that produced this event.
var predecessors: Array[SkillNode] = []

## The nth time this cast has landed on [member target], 0-based — the read
## an accumulation visual (Reverberator) collapses to noise without (#543 D6).
## Stamped from [method PropagationContext.visit_count] at resolve, BEFORE the
## bump, so a node struck three times reports 0, 1, 2. The count already
## existed on the context and was simply dropped on the floor.
var visit_index: int = 0

## The damage share each converging arc carried in, aligned index-for-index
## with [member predecessors] — entry `i` belongs to the predecessor at `i`.
## A single-incident landing carries exactly one entry, mirroring how
## [member predecessors] already behaves.
##
## This is what lets a merge be DRAWN as a merge (#704). The coordinator
## already spawns one bolt per [member predecessors] entry, and a Cyclone
## convergence is precisely a strong rank-1 arc meeting a weak rank-3 one —
## which is the reinforcement mechanic, and the only moment a player can see
## it. One scalar per landing would flatten exactly that.
##
## A float rather than the rank ordinal, deliberately: the ordinal loses
## [member CycloneStep.closing_gain], so a closing rank-1 arc would draw
## identically to an ordinary one — and a share is directly usable as a
## brightness or width scalar with no lookup table.
var incident_shares: PackedFloat32Array = PackedFloat32Array()

## The simple cycle this landing CLOSED, in walking order and ending at
## [member target] — empty on every landing that closed nothing (#710).
##
## The closing hop is Cyclone's payoff (the crit, plus
## [member CycloneStep.closing_gain] feeding forward as sustain) and it used to
## light, at most, one node. Lighting the ring AS a ring needs the ring, and
## nothing downstream can re-derive it: the walk that found it is
## [member CastSpell.visited], a resolver-local the event never carried.
##
## [b]Array order IS the storm's rotation[/b], so no [member turn_sign] read is
## needed to lap it. [method CycloneStep.closed_ring] returns the ring in walk
## order, which means consecutive pairs are its edges and the wraparound pair
## [code]ring[-1] → ring[0][/code] is the edge the closer just crossed — the Nth
## edge, not a seam to skip. Edges are derived at the VFX layer from those
## pairs; nothing promotes [Edge] objects.
##
## Node refs, the same precedent [member predecessors] and [member target]
## already set: an event is local replay output and never a command, so the
## sync rule's "no node refs on the wire" does not apply here.
var closed_ring: Array[SkillNode] = []

## Which way the storm turned to reach this landing — +1 / -1 / 0 for none.
## See [member CastSpell.turn_sign]; constant for a cast, carried per event
## because the VFX layer cannot honestly derive it.
var turn_sign: float = 0.0

## True when the propagation walk ENDED at this landing by terminal rule —
## hops exhausted, no step configured, or nothing left to expand to — as
## opposed to merely being the last event appended (#543 D6). Trail Blazer's
## junction slam is exactly "the entry where the walk ended", which was
## previously only inferable by re-deriving the resolver's own stopping
## condition in the VFX layer.
var is_terminal: bool = false

## The hit(s) this event lands — shared references into
## [member AttackOutcome.hits], NOT copies. Empty for [constant Verb.CANCEL]
## and for zero-damage / utility landings (which still get an event so the
## probe animates). #381: was a nullable [code]damage[/code]/[code]heal[/code]
## pair; one list holds either (or, once a landing can produce more than
## one, several).
var hits: Array[HitInstance] = []


## The highest [member HitInstance.crit_tier] across [member hits] — VFX
## emphasis is per-projectile / per-event, so this is a derived read rather
## than an event-owned field (crit-ness lives on the hit, #381 part 3).
func max_crit_tier() -> int:
	var best := 0
	for hit in hits:
		best = maxi(best, hit.crit_tier)
	return best


func _to_string() -> String:
	var verb_name: String = Verb.keys()[verb]
	var amt: float = hits[0].amount if not hits.is_empty() else 0.0
	return "<PropEvent b%d %s %s→%s %.1f>" % [beat, verb_name, origin, target, amt]
