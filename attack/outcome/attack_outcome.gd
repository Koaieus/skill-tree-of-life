class_name AttackOutcome
extends RefCounted

## The result of [method AttackPlan.resolve] — pure data describing what the
## attack would do. Used twice:
##   1. As a preview (UI tooltips, AI scoring) — call [method AttackPlan.resolve]
##      anytime to peek at current outcome.
##   2. As the commit payload — [BattleSystem.launch_attack] awaits VFX on it,
##      then applies each hit's damage.

## Every landing this outcome produced — damage and heals together (#381),
## in append order. Consumers that need damage specifically call
## [method damage_hits] rather than filtering with an `is` check.
var hits: Array[HitInstance] = []
## Action points consumed on commit.
var ap_cost: int = 1
## Mana consumed on commit. Spell plans copy from [member SpellDef.mana_cost];
## non-magic plans leave it at 0.
var mana_cost: int = 0
## Per-node fizzle records — populated when a spell's [IncidentReducer]
## returns null at a node (overlap-cancel, even-cancel, custom expression
## returning negative). VFX coordinators can render a dissipate effect at
## each entry's [member SpellCancellation.node].
var cancellations: Array[SpellCancellation] = []
## Spell-only structure over the same resolution, ordered by wave. Populated
## by [SpellResolver]; melee/ranged plans leave it empty. Each event's
## [member PropagationEvent.hits] entries are shared references into
## [member hits] (never copies). The VFX layer ([MagicBounceCoordinator])
## walks this — grouped by [member PropagationEvent.beat] — rather than
## re-deriving waves from [member hits]. See
## [code]docs/domain/spell-propagation.md[/code].
var timeline: Array[PropagationEvent] = []
## Count of the ATTACKER's own blade vertices lost to a defender's defensive-
## spike pop during this swing (see [BladePopResolver]). Zero for every other
## plan type — melee is the only mode that can cost the attacker's own shape
## mid-execution, which is what [AiCombatScorer]'s self-shape-risk term reads.
var thinned_nodes: int = 0
## The [member AttackPlan.resolve_seed] this outcome was resolved under, so
## the artifact is self-describing: it carries everything needed to reproduce
## itself. A peer handed (intent + this seed) re-resolves to a bit-identical
## outcome, which is what turns a desync check from "probably the same" into
## an exact comparison. 0 = resolved under the unstamped fixed stream (a
## preview or an AI rollout), never a real launch.
##
## [b]This does not make [AttackOutcome] wire-ready.[/b] [member hits] holds
## [HitInstance]s whose `target` / `origin` are live [SkillNode] REFERENCES
## and whose `source` is a [Variant]; per
## `docs/domain/multiplayer-sync-model.md` a command may only carry
## [member SkillNode.stable_id]. Serializing this type is its own unit.
var resolve_seed: int = 0


## [member hits] filtered to [constant HitInstance.Kind.DAMAGE] and cast —
## the "accepted cost" of unifying hits/heals into one list (#381). Reads
## [member HitInstance.kind], not `is DamageInstance`, so a hit
## [method SkillNode.take_damage] reclassified to a heal (Bulwark-style
## `min_damage_taken` underflow) correctly drops out here.
func damage_hits() -> Array[DamageInstance]:
	var out: Array[DamageInstance] = []
	for hit in hits:
		if hit.kind == HitInstance.Kind.DAMAGE:
			out.append(hit as DamageInstance)
	return out


func _to_string() -> String:
	return "<AttackOutcome %d hit(s), %d event(s), %d cancel(s), %d AP, %d mana>" % [
		hits.size(), timeline.size(), cancellations.size(), ap_cost, mana_cost]
