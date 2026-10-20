class_name Infusion
extends RefCounted

## A cast's infusion — the fifth spell component (ADR 0047, ADR 0060). Folds
## the spell's [member SpellDef.intakes] and the points spent into one load per
## concept ([method load_of]) and emits it as [OnHitEffect] riders
## ([method riders]) that [SpellResolver] runs after the spell's own
## [member SpellDef.on_hit_effects] at every landing. [method innate] is "the
## spell as authored"; [method for_cast] adds the points one cast spends,
## exchanged at affinity × ingest rate and floored.


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


## Total points this cast spends — what [member SpellDef.infusion_capacity]
## caps (there is no caster-side total; each aspect is capped by its own stat).
func total_points() -> int:
	var total := 0
	for id in points:
		total += points[id]
	return total


## The listed [AspectIntake] of [param spell] for concept [param id] (its
## first row), or null — an unlisted concept's affinity is 1:1.
static func intake_of(spell: SpellDef, id: StringName) -> AspectIntake:
	if spell == null:
		return null
	for intake in spell.intakes:
		if intake != null and intake.aspect_id() == id:
			return intake
	return null


## [param spell]'s whole exchange rate for concept [param id] as `(gain, cost)`:
## its affinity (1:1 unlisted) times the spell's ingest rate. Gain 0 refuses.
static func ratio_of(spell: SpellDef, id: StringName) -> Vector2i:
	if spell == null:
		return Vector2i(0, 1)
	var intake := intake_of(spell, id)
	var gain := intake.affinity_gain if intake != null else 1
	var cost := intake.affinity_cost if intake != null else 1
	return Vector2i(gain * spell.ingest_gain, cost * spell.ingest_cost)


## The load [param points] of concept [param id] add on [param spell]:
## `floor(points × gain / cost)`, exact integer arithmetic.
static func gained(spell: SpellDef, id: StringName, points: int) -> int:
	var ratio := ratio_of(spell, id)
	if points <= 0 or ratio.x <= 0:
		return 0
	@warning_ignore("integer_division")
	return (points * ratio.x) / ratio.y


## [method ratio_of] as one float — for display and the refusal test
## (`<= 0`) only; never multiply points by it, use [method gained].
static func rate_of(spell: SpellDef, id: StringName) -> float:
	var ratio := ratio_of(spell, id)
	return float(ratio.x) / ratio.y


## `{concept id: load}` — the spell's innate per listed concept (two rows for
## one concept sum), plus [method gained] for every concept this cast infuses.
## Listed concepts in authored order, then infused ones.
func load_of(spell: SpellDef) -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	if spell == null:
		return out
	for intake in spell.intakes:
		if intake == null or intake.identity == null:
			continue
		var id := intake.aspect_id()
		out[id] = out.get(id, 0) + intake.innate
	for id in points:
		out[id] = out.get(id, 0) + gained(spell, id, points[id])
	return out


## The explosive load this cast spends at each hit as a blast: the
## `explosive` load iff its face resolves DETONATE ([method face_of]), else 0
## — a FUEL row's load only shapes the spell, a PLANT row's lands as a rider.
func detonate_load(spell: SpellDef) -> int:
	if face_of(spell, DetonateEffect.EXPLOSIVE) != AspectIntake.Face.DETONATE:
		return 0
	return load_of(spell).get(DetonateEffect.EXPLOSIVE, 0)


## The face concept [param id] resolves to on [param spell]: its intake row's
## [method AspectIntake.resolved_face], else — an infused concept with no row —
## its status's default ([method AspectIntake.face_of_status]).
static func face_of(spell: SpellDef, id: StringName) -> AspectIntake.Face:
	var row := intake_of(spell, id)
	if row != null:
		return row.resolved_face()
	return AspectIntake.face_of_status(StatusRoster.shared().by_concept(id))


## One [ApplyStatusEffect] per PLANT concept ([method face_of]) whose load is
## above zero, carrying that concept's status at `power = load`. A DETONATE
## load is spent at the hit ([method detonate_load]); a FUEL load only shapes
## the spell.
## Fresh effects per call — the resolver builds them once per cast.
func riders(spell: SpellDef) -> Array[OnHitEffect]:
	var out: Array[OnHitEffect] = []
	if spell == null:
		return out
	var counts := load_of(spell)
	for id in counts:
		if counts[id] <= 0:
			continue
		if face_of(spell, id) != AspectIntake.Face.PLANT:
			continue
		var status := StatusRoster.shared().by_concept(id)
		if status == null:
			continue
		var rider := ApplyStatusEffect.new()
		rider.def = status
		rider.power = float(counts[id])
		var row := intake_of(spell, id)
		if row != null:
			rider.stack_terms = row.stack_terms.duplicate()
			rider.power_from = row.power_from
		out.append(rider)
	return out
