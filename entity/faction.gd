@tool
class_name Faction
extends Resource

## A team identity composed onto an [Entity] (parallel to [CoreClass]) —
## singular [member Entity.faction], not plural, deliberately: an entity in
## multiple factions needs a resolution policy nobody has designed yet (see
## #384). Carries display name + color for the HUD and is a place to hang
## attitude overrides later without touching call sites.
##
## Identity is by [member id], not resource reference — a `.tres` loaded twice
## or `duplicate()`d must still compare equal. [method Entity.attitude_to] is
## the one place that relation is decided; this resource carries no logic of
## its own. Mirrors [code]StatDef[/code] (`stats_system/stat_def.gd`): id +
## display name + tint colour.

@export var id: StringName = &""
@export var display_name: String = ""
@export var color: Color = Color.WHITE

## Is this a camp that can win or lose a run? (#460). Authored, not inferred:
## a hard-coded [code]if faction.id == &"npc"[/code] at the victory check would
## be a second definition of "who is a real camp", living somewhere no designer
## will look. [LastCampStandingCondition] ignores entities whose faction says
## false — so a board holding nothing but dormant cores is already won.
##
## False only on `blocker.tres` (the dormant-core camp): removable blockers
## (#300) are inert scenery that own a node and never act. Every playable camp
## — `player`, `npc`, `camp_1..4` — leaves this true.
@export var counts_for_victory: bool = true

## Do NPC brains spend their turn shooting at this camp? False only on
## `blocker.tres`: a dormant core is scenery a *player* may want to clear, so
## it stays [constant Entity.Attitude.HOSTILE] — the relation is what lets
## anyone attack it at all, and lets the forced-dealloc cascade and XP gating
## treat a cleared blocker as a real kill. This flag is strictly about AI
## attention: [method AiRecon.visible_enemy_nodes] drops these nodes, so the
## whole NPC pipeline downstream of it (growth's directional bias, the
## `saw_hostile` short-circuit, ranged/magic/melee candidate enumeration)
## never sees them.
##
## Deliberately NOT folded into [member counts_for_victory] and deliberately
## NOT expressed in [method Entity.attitude_to]: "can end the run" and "worth
## an NPC's AP" are different questions that happen to coincide on one
## resource today, and moving either into the attitude relation would silently
## disarm the *player* too.
@export var targeted_by_ai: bool = true
