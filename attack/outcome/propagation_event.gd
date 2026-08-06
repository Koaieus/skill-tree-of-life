class_name PropagationEvent
extends RefCounted

## One beat in a spell's propagation, as the [SpellResolver] emits it. The
## VFX layer ([MagicBounceCoordinator]) walks a [member AttackOutcome.timeline]
## of these — grouped by [member beat] — instead of re-deriving wave structure
## from [member AttackOutcome.hits]. See [code]docs/domain/spell-propagation.md[/code]
## ("The outcome → VFX seam").
##
## The timeline is **additive** over [member AttackOutcome.hits]: an event's
## [member damage] is a *shared reference* into that same flat list (or null
## for [constant Verb.CANCEL] / zero-damage landings), never a copy.

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

## The hit this event lands — a shared reference into [member AttackOutcome.hits],
## NOT a copy. Null for [constant Verb.CANCEL] and for zero-damage / utility
## landings (which still get an event so the probe animates).
var damage: DamageInstance = null
## The heal this event lands  
var heal: HealingInstance = null
# TODO: refactor these two variables to a single var typed to parent type? 
#		possibly as array too (would allow multiple instances, 
#		currently not the case but wouldn't limit us either

## Crit stacking tier — 0 = no crit, 1 = crit, ≥2 = multi-source. Always 0
## until crits land (#195 / #197); the VFX layer reads it for emphasis.
var crit_tier: int = 0


func _to_string() -> String:
	var verb_name: String = Verb.keys()[verb]
	var amt: float = damage.amount if damage != null else 0.0
	return "<PropEvent b%d %s %s→%s %.1f>" % [beat, verb_name, origin, target, amt]
