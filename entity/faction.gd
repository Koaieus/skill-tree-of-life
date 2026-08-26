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
## [b]It is the default stance, not an absolute[/b] (#604). An NPC that is
## growth-capped — walled in with no node left to allocate — flips
## [member Entity.ai_growth_capped] on for that turn and does see them,
## because the camp it is indifferent to has become the thing stopping it from
## playing. Read this flag as "worth an NPC's AP under normal circumstances";
## [method AiRecon.is_ai_target] owns the exception.
##
## Deliberately NOT expressed in [method Entity.attitude_to]: "worth an NPC's
## AP" and "may be attacked at all" are different questions, and moving this
## into the attitude relation would silently disarm the *player* too.
##
## It is also NOT the sibling of contest membership any more. "Can end the run"
## left [Faction] entirely in #517 — it is a [ContestantRule] the victory
## condition owns, keyed on a per-entity group — because it needed a per-entity
## answer. This flag stays camp-level on purpose: you shoot at camps, not
## individuals. (A per-entity `targeted_by_ai` would be a drop-in on the same
## group, since [method AiRecon.visible_enemy_nodes] already resolves this per
## owning entity — but that is its own decision, not a consequence of #517.)
@export var targeted_by_ai: bool = true
