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
