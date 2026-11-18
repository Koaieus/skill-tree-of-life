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

## The cast's forged **shape** element (ADR 0085 §1) and the points it draws
## from that element's count. Inert here: stored, count-checked, remembered and
## wired, never read by the walk, the seed or the load. `&""` or 0 = none.
var shape_element: StringName = &""
var shape_points: int = 0
## The cast's forged **ride**: one terrain element whose load replaces or adds
## to the spell's innate ride ([method load_of]). `&""` or 0 = none. Neither
## field takes an aspect slot nor counts in [method total_points].
var ride_element: StringName = &""
var ride_points: int = 0


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


## [method for_cast] of [param spent] carrying this infusion's shape and ride —
## the one rebuild that never drops the two element fields.
func rebuilt(spell: SpellDef, spent: Dictionary) -> Infusion:
	var out := Infusion.for_cast(spell, spent)
	out.set_shape(shape_element, shape_points)
	out.set_ride(ride_element, ride_points)
	return out


## Forge [param points] of element [param id] as the shape; an empty id, an id
## that names no [Element] (an aspect never fills a field) or non-positive
## points clears it.
func set_shape(id: StringName, points_in: int) -> void:
	var on := is_element(id) and points_in > 0
	shape_element = id if on else &""
	shape_points = points_in if on else 0


## Forge [param points] of element [param id] as the ride; cleared as
## [method set_shape] is.
func set_ride(id: StringName, points_in: int) -> void:
	var on := is_element(id) and points_in > 0
	ride_element = id if on else &""
	ride_points = points_in if on else 0


## True iff [param id] names an [Element] (`&"fire"`, `&"ice"`, `&"lightning"`).
static func is_element(id: StringName) -> bool:
	return not id.is_empty() and ElementRoster.shared().by_id(id) != null


## True iff [param intake] is an element ride row: its identity is an
## [Element]'s. The one predicate [method innate_ride_of], [method load_of] and
## the def lint read.
static func is_ride_row(intake: AspectIntake) -> bool:
	return intake != null and intake.identity != null and is_element(intake.aspect_id())


## The element [param spell]'s ride rows carry (at most one per def), else `&""`.
static func innate_ride_of(spell: SpellDef) -> StringName:
	if spell == null:
		return &""
	for intake in spell.intakes:
		if is_ride_row(intake):
			return intake.aspect_id()
	return &""


## Which terrain element this cast's hits plant: the forged ride, else the
## spell's innate ride, else `&""`.
func ride_of(spell: SpellDef) -> StringName:
	return ride_element if ride_points > 0 else innate_ride_of(spell)


## The element this cast is shaped by: the forged shape, else the spell's
## authored shape default (none exists yet), else `&""`.
func shape_of(_spell: SpellDef) -> StringName:
	return shape_element if shape_points > 0 else &""


## Points this cast draws from [param element]'s count: the shape's if it is
## that element plus the ride's if it is. The one count-spend read.
func spent_on(element: StringName) -> int:
	var out := 0
	if shape_points > 0 and shape_element == element:
		out += shape_points
	if ride_points > 0 and ride_element == element:
		out += ride_points
	return out


## The two element fields as wire/memory form: `"shape"` and `"ride"`, each
## `{id, points}`, each only when set.
func fields_to_dict() -> Dictionary:
	var d := {}
	if shape_points > 0:
		d["shape"] = {"id": String(shape_element), "points": shape_points}
	if ride_points > 0:
		d["ride"] = {"id": String(ride_element), "points": ride_points}
	return d


## Read [method fields_to_dict]'s form back into this infusion, ungated.
func read_fields(d: Dictionary) -> void:
	var shape: Dictionary = d.get("shape", {}) as Dictionary
	var ride: Dictionary = d.get("ride", {}) as Dictionary
	set_shape(StringName(shape.get("id", "")), int(shape.get("points", 0)))
	set_ride(StringName(ride.get("id", "")), int(ride.get("points", 0)))


## Aspects this cast spends points on — what `infusion_slots` caps.
func slots_used() -> int:
	return points.size()


## Total points this cast spends on its aspects — what
## [member SpellDef.infusion_capacity] caps (there is no caster-side total; each
## aspect is capped by its own stat). The shape and the ride sit outside the cap
## (ADR 0094 §6): their points are never in it.
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
## Listed concepts in authored order, then infused ones. The forged ride adds
## its [method gained] to its element: on the innate ride's element it adds to
## those rows; on another element the innate ride's rows are suppressed for
## this cast (the def is untouched), so a hit carries 0 or 1 element. The shape
## never enters the load.
func load_of(spell: SpellDef) -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	if spell == null:
		return out
	var innate_ride := innate_ride_of(spell)
	var suppressed := innate_ride \
			if ride_points > 0 and ride_element != innate_ride else &""
	for intake in spell.intakes:
		if intake == null or intake.identity == null:
			continue
		var id := intake.aspect_id()
		if not suppressed.is_empty() and id == suppressed and is_ride_row(intake):
			continue
		out[id] = out.get(id, 0) + intake.innate
	for id in points:
		out[id] = out.get(id, 0) + gained(spell, id, points[id])
	if ride_points > 0:
		out[ride_element] = out.get(ride_element, 0) + gained(spell, ride_element, ride_points)
	return out


## The [LoadUse] concept [param id] resolves to on [param spell]: its intake
## row's [method AspectIntake.resolved_use], else — an infused concept with no
## row — the shared default ([method AspectIntake.default_use]).
static func use_of(spell: SpellDef, id: StringName) -> LoadUse:
	var row := intake_of(spell, id)
	if row != null:
		return row.resolved_use()
	return AspectIntake.default_use()


## The status concept [param id] lands as on [param spell]: its listed row's
## [method AspectIntake.status] (its `plants` when set), else the concept's only
## status ([method AspectIntake.concept_status]). The one status lookup here.
static func status_of(spell: SpellDef, id: StringName) -> StatusDef:
	var row := intake_of(spell, id)
	return row.status() if row != null else AspectIntake.concept_status(id)


## The [OnHitEffect] riders this cast runs after the spell's own effects — one
## [ApplyStatusEffect] per [PlantUse] concept with a status, at `power = load`
## ([method bag]). Fresh effects per call — the resolver builds them once per
## cast.
func riders(spell: SpellDef) -> Array[OnHitEffect]:
	return bag(spell).riders


## One walk over [method load_of]: every concept whose load is above zero
## spends it through its [method use_of] ([method LoadUse.spend]) into a fresh
## [LoadBag].
func bag(spell: SpellDef) -> LoadBag:
	var out := LoadBag.new()
	if spell == null:
		return out
	var counts := load_of(spell)
	for id in counts:
		if counts[id] <= 0:
			continue
		use_of(spell, id).spend(intake_of(spell, id), status_of(spell, id), counts[id], out)
	return out
