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


## The concept id this affinity keys on (`&"poison"`) — the status's
## [member StatusDef.identity], falling back to its own id; `&""` unset.
func aspect_id() -> StringName:
	if status == null:
		return &""
	if status.identity != null and not status.identity.id.is_empty():
		return status.identity.id
	return status.id


## The on-arrival line: the innate stacks per hit through
## [method StatusDef.stacks_per_hit] — the fold the landing itself uses, so a
## [param board] carrying the attacker's `<family>_stacks_per_hit` scales it
## here exactly as it scales the rider — then how the spell ingests an
## infusion of this concept.
func get_description(board: StatBoard = null) -> String:
	if status == null:
		return "Applies nothing (no status set)."
	var name := status.display_name if not status.display_name.is_empty() else String(status.id)
	var stacks := status.stacks_per_hit(board, float(innate))
	var concept := name.to_lower()
	var ingest := "refuses %s infusions" % concept if is_zero_approx(rate) \
			else "+%s per %s infused" % [NumFmt.num(rate), concept]
	return "Applies %s (%s per hit; %s)." % [name, NumFmt.num(stacks), ingest]
