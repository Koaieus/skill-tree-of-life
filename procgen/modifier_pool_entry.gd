@tool
class_name ModifierPoolEntry
extends Resource

## One pick option in a [ModifierPool]. The entry IS a tier: it carries the
## `(stat_id, operation, value_range)` triple plus `cost` (budget axis) and
## `weight` (sampling axis). [method roll] mints a fresh scalar [StatModifier]
## by sampling `value_range` — `StatModifier` itself stays range-free; the
## value-range concern lives at procgen roll time only.
##
## `id` is the stable handle weight profiles key off (collision detection,
## archetype boosts, etc.). It defaults to empty; designers should set it
## per entry — `_get_configuration_warnings()` flags omissions.
##
## `tags` is the designer's flavour vocabulary — `[&"str", &"flat", &"tier_2"]`
## etc. Profiles work on tags, never on entry ids beyond collision-keying.
## Tags are validated against [TagRegistry] (`procgen/tags.tres`).

@export var id: StringName = &""
@export var stat_id: StringName = &""
@export var operation: StatModifier.Operation = StatModifier.Operation.ADD_BASE
## Inclusive range sampled at roll time. Both ends equal → fixed value.
@export var value_range: Vector2 = Vector2(1.0, 1.0)
## Budget cost — see [ModifierPool.roll]. Floor of 1 keeps per-node draw count
## bounded (no cost-0 entries).
@export var cost: int = 1
## Base sampling weight before [WeightProfile] modulation.
@export var weight: float = 1.0
## Flavour tags. Validated against [TagRegistry].
@export var tags: Array[StringName] = []


## Mints a fresh [StatModifier]. The value is sampled from `value_range` and
## coerced via the target stat's `value_type` (INT pools snap, FLOAT pools
## don't). Pool definitions are never mutated.
func roll(rng: RandomNumberGenerator) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = operation
	var v := rng.randf_range(value_range.x, value_range.y)
	m.value = _coerce_to_stat_type(v, operation)
	return m


## Coerces only the operations whose `value` flows through the target stat's
## value_type. ADD_BASE/ADD_BONUS deliver a raw amount in the stat's units —
## INT-typed stats want whole numbers there. INCREASE is percent-points and
## MULTIPLY is a raw scalar (×1.07 etc.) — both are stat-type-agnostic;
## coercing them would round `×1.07 INT` to `×1.0 INT`, destroying the roll.
func _coerce_to_stat_type(v: float, op: int) -> float:
	if op != StatModifier.Operation.ADD_BASE and op != StatModifier.Operation.ADD_BONUS:
		return v
	if StatRegistry == null:
		return v
	var def: StatDef = StatRegistry.get_def(stat_id)
	if def == null:
		return v
	match def.value_type:
		StatDef.ValueType.INT:
			return float(int(round(v)))
		StatDef.ValueType.BOOL:
			return 1.0 if v != 0.0 else 0.0
		_:
			return v


func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	if id == &"":
		out.append("id should be set — weight profiles key off id for stable lookups.")
	if stat_id == &"":
		out.append("stat_id is empty — entry will mint a StatModifier targeting nothing.")
	if cost < 1:
		out.append("cost should be ≥ 1 — cost-0 entries break the per-node draw cap.")
	if value_range.x > value_range.y:
		out.append("value_range.x (%s) > value_range.y (%s) — randf_range will return value_range.x." % [value_range.x, value_range.y])
	var registry := TagRegistry.canonical()
	if registry != null:
		var unknown := registry.unknown_tags(tags)
		for t in unknown:
			out.append("unknown tag: %s (not in procgen/tags.tres)" % String(t))
	return out
