@tool
class_name Archetype
extends Resource
## One archetype's identity: the stat it is themed around, and the central
## CARVE shape that reads it at a glance. The colour is DERIVED from the
## primary stat's [StatDef.tint_color] — never authored here, so there is no
## second palette to drift (see #302).
@export var id: StringName = &""
## Any [StatRegistry] id. NOT restricted to the six primary attributes — those
## are siblings of e.g. `crit_chance` on the same stat board, so a crit-chance
## territory is just `primary_stat = &"crit_chance"`.
@export var primary_stat: StringName = &""
## The central shape carved into the node's dome — meant to be recognisable at
## a glance, at a distance, on an otherwise-empty node. Archetype never
## interprets WHAT the shape is (polygon vs. gem vs., later, arbitrary art); it
## just holds the reference.
##
## TODO(#246): wisdom.tres's hexagon is a placeholder pending a bespoke
## "exudes wealth" motif (coin/laurel/sunburst) once the arbitrary-art bake
## pipeline lands — not a deliberate design pick. Carried over from the note
## on the retired enum-based predecessor (#312).
@export var carve_shape: CarveShape = null

var color: Color:
	get: return StatRegistry.get_def(primary_stat).tint_color
