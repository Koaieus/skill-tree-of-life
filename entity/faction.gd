@tool
class_name Faction
extends Resource

## A team identity composed onto an [Entity] (parallel to [CoreClass]) —
## singular [member Entity.faction], not plural, deliberately: an entity in
## multiple factions needs a resolution policy nobody has designed yet (see
## #384). Carries display name + color for the HUD and is a place to hang
## attitude overrides later without touching call sites.
##
## Identity is by resource reference — two entities sharing the SAME `.tres`
## are on the same team. [method Entity.attitude_to] is the one place that
## relation is decided; this resource carries no logic of its own.

@export var display_name: String = ""
@export var color: Color = Color.WHITE
