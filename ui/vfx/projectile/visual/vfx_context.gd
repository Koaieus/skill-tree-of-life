@tool
class_name VfxContext
extends RefCounted

## Duck-typed reads off #543 D6's `ScheduleEntry` (hop fraction, normalized
## magnitude, convergence count, `visit_index`, `is_terminal`).
##
## [b]Why this exists as a helper rather than a type.[/b] The visual contract is
## deliberately duck-typed — "any subset, all optional" — and every visual's
## `_on_context(entry)` therefore declares its parameter as [Variant], not as
## `ScheduleEntry`. That is not a temporary workaround for a class that has not
## landed yet; it is what lets a visual keep working when a coordinator hands it
## a shape it does not read. So the read side needs one careful accessor, and
## exactly one, rather than a defensive `if field in obj` at every call site.
##
## Once #543 merges, a visual that genuinely needs a field may tighten its own
## parameter type in its own unit. This helper stays useful for the ones that
## should stay tolerant.

## Numeric field off an entry, or [param fallback] when it is absent, null, or
## not a number. Accepts an [Object] (property lookup) or a [Dictionary] (key
## lookup), so a test can stand in for the real entry with a literal.
static func read_float(entry: Variant, field: StringName, fallback: float) -> float:
	if entry is Object:
		var obj: Object = entry
		if field in obj:
			var v: Variant = obj.get(field)
			if v is float or v is int:
				return float(v)
	elif entry is Dictionary:
		var d: Dictionary = entry
		if d.has(field):
			var v: Variant = d[field]
			if v is float or v is int:
				return float(v)
	return fallback


## Boolean field off an entry (`is_terminal` is the one #543 D6 names), or
## [param fallback] when absent.
static func read_bool(entry: Variant, field: StringName, fallback: bool) -> bool:
	if entry is Object:
		var obj: Object = entry
		if field in obj:
			var v: Variant = obj.get(field)
			if v is bool:
				return v
	elif entry is Dictionary:
		var d: Dictionary = entry
		if d.has(field):
			var v: Variant = d[field]
			if v is bool:
				return v
	return fallback
