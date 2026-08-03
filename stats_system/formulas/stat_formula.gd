@tool
@abstract
class_name StatFormula
extends Resource

## Abstract base for pluggable stat formulas used by [StatModifier].
## A formula is stateless — it reads from the board it is given and returns
## a float. All binding/subscription state lives on [StatModifier].

## The qualifier phrase rendered after "per" by [method StatModifier.format]
## — "20 STR", "PER", "×10 INT", "level". ONE SHORT LINE, never
## prose: a formula-bound modifier is displayed as a single-Label glass slab
## ([ModSlabRow]) inside a hover tooltip, so "+1 Blade Size per 20 STR" is the
## entire budget. Deliberately NOT `@export_multiline` (#289).
##
## Subclasses that know their own shape generate this from their typed fields
## (see [RatioFormula], [LinearFormula]) and only fall back to the authored
## string. Author it here for [ExpressionFormula]s, whose expression text is
## arbitrary and must never be parsed back into English.
@export var per_phrase: String = ""

## Ids of all stats this formula reads. [StatModifier] subscribes to
## value_changed on each so the target stat can dirty itself automatically.
func get_input_ids() -> Array[StringName]:
	return []

## Compute and return the modifier value. Called from
## [method StatModifier.get_effective_value] every time the pipeline runs.
func compute(board: StatBoard) -> float:
	return 0.0


## The "per" qualifier for this formula. Base implementation returns the
## authored [member per_phrase]; shape-aware subclasses override to generate
## it, honouring an authored override when one is present.
func describe_per() -> String:
	return per_phrase


## Abbreviation for a source stat, matching the Attributes Panel's axis
## labels (`Strength` → `STR`). Lives here so generated phrases and the
## panel share one convention — see [method StatDef.abbrev].
static func _abbrev(stat_id: StringName) -> String:
	var def: StatDef = StatRegistry.get_def(stat_id)
	return def.abbrev() if def != null else String(stat_id)


# --- Accessor-token split (#333) ---------------------------------------------
#
# A formula token is either a bare `<stat_id>` (no `__`) — read the stat's
# computed value / cap — or `<stat_id>__<accessor>` — read one of the stat's
# named accessors through [method Stat.read_accessor]. The join is `__`
# (double underscore), not `_`: stat ids contain single underscores
# (`min_damage_taken`, `deallocation_points`), so a single-`_` join is
# ambiguous to split. `:` / `::` parse cleanly under [method Expression.parse]
# but fail at [method Expression.execute] with the misleading "self can't be
# used because instance is null" — verified empirically, do not re-litigate.
#
# The dependency graph keeps seeing the BASE id — `get_input_ids()` strips
# through [method base_of]. A cycle running through a pool read via
# `__current` is an edge back to the pool's base id, exactly the case
# [method StatBoard.cycle_from] (#322) exists to catch.

## The base stat id of a formula token — `<stat_id>` for a bare token, or
## the prefix before `__` for a decorated one. Static so subclasses share
## one definition; pure (no state) so it composes across the formula layer.
static func base_of(token: StringName) -> StringName:
	var s := String(token)
	var sep := s.find("__")
	if sep < 0:
		return token
	return StringName(s.substr(0, sep))


## The accessor name of a formula token — `&""` for a bare token (the
## computed value / cap), or the suffix after `__` for a decorated one.
static func accessor_of(token: StringName) -> StringName:
	var s := String(token)
	var sep := s.find("__")
	if sep < 0:
		return &""
	return StringName(s.substr(sep + 2))


## True iff the token names a formula accessor, not a stat — i.e. it
## contains `__`. Used to gate registration paths that must reject decorated
## tokens ([method StatBoard._ensure_stat], a modifier's `stat_id`): these
## are formula-read tokens, NOT stats. No [StatDef], no [StatRegistry] entry.
## See #333 → Decision 7.
static func is_accessor_token(token: StringName) -> bool:
	return String(token).find("__") >= 0


## Render a float without trailing ".00" — whole values print as ints.
## Mirrors [method StatModifier._trim]; duplicated rather than reached for
## across the formula/modifier boundary, which points the other way.
static func _trim(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return "%d" % roundi(v)
	return ("%.2f" % v).trim_suffix("0")
