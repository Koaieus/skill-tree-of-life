class_name Infusion
extends RefCounted

## A cast's infusion — the fifth spell component (ADR 0047). Folds the
## spell's [member SpellDef.affinities] into one count per concept
## ([method affinity_of]) and emits it as [OnHitEffect] riders
## ([method riders]) that [SpellResolver] runs after the spell's own
## [member SpellDef.on_hit_effects] at every landing. This half carries no
## points: [method innate] is "the spell as authored", which is what a cast
## with nothing spent resolves with.


var points: Dictionary[StringName, int] = {}


static func for_cast(spell: SpellDef, _points: Dictionary) -> Infusion:
	return innate(spell)


func slots_used() -> int:
	return 0


## The spell's innate infusion — no points spent.
static func innate(_spell: SpellDef) -> Infusion:
	return Infusion.new()


## `{concept id: affinity}` for every concept [param spell] lists, in authored
## order; two entries for one concept sum. An entry with no status is skipped.
func affinity_of(spell: SpellDef) -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	if spell == null:
		return out
	for affinity in spell.affinities:
		if affinity == null or affinity.status == null:
			continue
		var id := affinity.aspect_id()
		out[id] = out.get(id, 0) + affinity.innate
	return out


## One [ApplyStatusEffect] per concept whose affinity is above zero, carrying
## that concept's status at `power = affinity`. Fresh effects per call — the
## resolver builds them once per cast.
func riders(spell: SpellDef) -> Array[OnHitEffect]:
	var out: Array[OnHitEffect] = []
	if spell == null:
		return out
	var status_of: Dictionary[StringName, StatusDef] = {}
	for affinity in spell.affinities:
		if affinity != null and affinity.status != null:
			status_of.get_or_add(affinity.aspect_id(), affinity.status)
	var counts := affinity_of(spell)
	for id in counts:
		if counts[id] <= 0:
			continue
		var rider := ApplyStatusEffect.new()
		rider.def = status_of[id]
		rider.power = float(counts[id])
		out.append(rider)
	return out
