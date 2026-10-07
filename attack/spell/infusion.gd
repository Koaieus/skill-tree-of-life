class_name Infusion
extends RefCounted

## A cast's infusion — the fifth spell component (ADR 0047). Folds the
## spell's [member SpellDef.affinities] into one count per concept
## ([method affinity_of]) and emits it as [OnHitEffect] riders
## ([method riders]) that [SpellResolver] runs after the spell's own
## [member SpellDef.on_hit_effects] at every landing. [method innate] is "the
## spell as authored"; [method for_cast] adds the points one cast spends,
## ingested at the spell's per-concept rate and floored.


## Points spent on this cast, `{concept id: points}` — what the plan ships and
## the host's [method MagicAttackPlan.aspect_overrun] caps. Empty = innate.
var points: Dictionary[StringName, int] = {}


## The spell's innate infusion — no points spent.
static func innate(_spell: SpellDef) -> Infusion:
	return Infusion.new()


## An infusion spending [param spent] (`{concept id: points}`, any key type
## [StringName] accepts) on one cast; non-positive entries are dropped.
static func for_cast(_spell: SpellDef, spent: Dictionary) -> Infusion:
	var out := Infusion.new()
	for key in spent:
		var n := int(spent[key])
		if n > 0:
			out.points[StringName(key)] = n
	return out


## Aspects this cast spends points on — what `infusion_slots` caps.
func slots_used() -> int:
	return points.size()


## Total points this cast spends — what `infusion_points` caps.
func total_points() -> int:
	var total := 0
	for id in points:
		total += points[id]
	return total


## [param spell]'s ingest ratio for concept [param id]: its listed
## [member SpellAffinity.rate], else [member SpellDef.default_rate].
static func rate_of(spell: SpellDef, id: StringName) -> float:
	if spell == null:
		return 0.0
	for affinity in spell.affinities:
		if affinity != null and affinity.status != null and affinity.aspect_id() == id:
			return affinity.rate
	return spell.default_rate


## `{concept id: affinity}` — the spell's innate count per listed concept (two
## entries for one concept sum), plus `floor(points × rate)` for every concept
## this cast spends on. Listed concepts in authored order, then infused ones.
func affinity_of(spell: SpellDef) -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	if spell == null:
		return out
	for affinity in spell.affinities:
		if affinity == null or affinity.status == null:
			continue
		var id := affinity.aspect_id()
		out[id] = out.get(id, 0) + affinity.innate
	for id in points:
		out[id] = out.get(id, 0) + floori(points[id] * rate_of(spell, id))
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
	for id in points:
		if not status_of.has(id):
			var status := StatusRoster.shared().by_concept(id)
			if status != null:
				status_of[id] = status
	var counts := affinity_of(spell)
	for id in counts:
		if counts[id] <= 0 or not status_of.has(id):
			continue
		var rider := ApplyStatusEffect.new()
		rider.def = status_of[id]
		rider.power = float(counts[id])
		out.append(rider)
	return out
