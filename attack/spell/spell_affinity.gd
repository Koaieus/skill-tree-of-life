@tool
class_name SpellAffinity
extends Resource

## One entry of a spell's element list (#1250): the spell carries [member innate]
## points of [member status]'s concept by default, and ingests an infusion of
## that concept at [member rate] (`affinity += floor(points × rate)`; 0 refuses
## it). What lands per hit is `affinity` stacks through the status's own
## [method StatusDef.stacks_per_hit] fold — see [Infusion]. Points at the
## [StatusDef], never the [Aspect]: an Aspect lists its spells, so an edge back
## would be a resource cycle; the status's [member StatusDef.identity] is the
## concept's id.

## The status this affinity lands — the concept's [member Aspect.status].
@export var status: StatusDef = null:
	set(value):
		status = value
		emit_changed()
## Points the spell carries with no infusion spent.
@export_range(0, 100, 1, "or_greater") var innate: int = 0:
	set(value):
		innate = maxi(value, 0)
		emit_changed()
## Ingest ratio for an infusion of this concept; 0 disables it.
@export_range(0.0, 10.0, 0.05, "or_greater") var rate: float = 1.0:
	set(value):
		rate = maxf(value, 0.0)
		emit_changed()


## The concept id this affinity keys on (`&"poison"`), or `&""` unset.
func aspect_id() -> StringName:
	return &""


func get_description(_board: StatBoard = null) -> String:
	return ""
