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
