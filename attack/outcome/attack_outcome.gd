class_name AttackOutcome
extends RefCounted

## The result of [method AttackPlan.resolve] — pure data describing what the
## attack would do. Used twice:
##   1. As a preview (UI tooltips, AI scoring) — call [method AttackPlan.resolve]
##      anytime to peek at current outcome.
##   2. As the commit payload — [BattleSystem.launch_attack] awaits VFX on it,
##      then applies each hit's damage.

var hits: Array[DamageInstance] = []
var heals: Array[HealingInstance] = []
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
## [member PropagationEvent.damage] is a shared reference into [member hits]
## (never a copy). The VFX layer ([MagicBounceCoordinator]) walks this — grouped
## by [member PropagationEvent.beat] — rather than re-deriving waves from [member
## hits]. See [code]docs/domain/spell-propagation.md[/code].
var timeline: Array[PropagationEvent] = []


func _to_string() -> String:
	return "<AttackOutcome %d hit(s), %d heals(s), %d event(s), %d cancel(s), %d AP, %d mana>" % [
		hits.size(), heals.size(), timeline.size(), cancellations.size(), ap_cost, mana_cost]
