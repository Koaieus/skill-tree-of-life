@tool
class_name ArrowPart
extends Node2D

## One piece of a [StatusArrow]'s look — a tip, a shed emitter, an impact
## emitter, an impact sprite. A look is a `.tscn` of the base arrow that adds or
## configures parts; [StatusArrow] finds every [ArrowPart] child and drives it
## through one lifecycle, so no look scripts the arrow itself:
##
##   [method paint]        — the shot's status colour, or a dud / absorb verdict
##   [method launch]       — the arrow leaves the string (only with a status)
##   [method stop]         — the arrow struck, or was spent; stop emitting
##   [method arrive]       — the landing counted: play the impact at [ArrowImpactContext]
##   [method drain_seconds] — how long this part outlives its own stop
##
## A part reads only its arguments and its own exports, never the arrow or a
## [SkillNode]. Who shows on a dud or an absorbed shot is the two flags below,
## applied here once; a part never re-decides it.

## Stays visible (repainted as spent) when the shot lands a dud.
@export var show_on_dud: bool = false
## Stays visible when the defender absorbed the shot — the arrow then speaks
## for the defender ([method LightArrow._on_absorbed]), so status parts step aside.
@export var show_on_absorbed: bool = false
## Fades with the shaft after the strike ([member CanvasItem.self_modulate] alpha).
## Emitters leave it off: their particles drain on their own lifetime.
@export var fades_with_shaft: bool = false


## Repaint for [param tint] (SDR status colour, alpha 0 = no status). The base
## owns visibility; an override calls `super` and then lifts the colour to its
## own [Emissive] tier.
func paint(tint: Color, dud: bool, absorbed: bool) -> void:
	visible = tint.a > 0.0 and (show_on_dud or not dud) and (show_on_absorbed or not absorbed)


func launch() -> void:
	pass


func arrive(_ctx: ArrowImpactContext) -> void:
	pass


func stop() -> void:
	pass


func drain_seconds() -> float:
	return 0.0


## [param tint] as an opaque colour at [param tier] — the one lift every part uses.
static func lit(tint: Color, tier: Emissive.Tier) -> Color:
	return Emissive.at(Color(tint.r, tint.g, tint.b, 1.0), Emissive.stops(tier))
