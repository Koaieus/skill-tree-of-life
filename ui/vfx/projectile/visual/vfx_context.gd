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


## An endpoint field off an entry ([code]origin[/code]/[code]target[/code],
## #543 D6), as a [Node2D], or null when absent or the wrong shape. Accepts
## an [Object] (property lookup, the real [ScheduleEntry] shape) or a
## [Dictionary] (key lookup), same as [method read_float]/[method read_bool],
## so a test can stand in for the real entry with a literal.
static func read_node2d(entry: Variant, field: StringName) -> Node2D:
	if entry is Object:
		var obj: Object = entry
		if field in obj:
			var v: Variant = obj.get(field)
			if v is Node2D:
				return v
	elif entry is Dictionary:
		var d: Dictionary = entry
		if d.has(field):
			var v: Variant = d[field]
			if v is Node2D:
				return v
	return null


## Normalized hop fraction in 0..1 — the one input a per-hop heat/size ramp
## reads (Lightning attenuates outward, Leafblower grows).
##
## [b]Why this is derived rather than read.[/b] #543 landed the quantity as the
## PAIR [code]beat_index[/code] / [code]beat_count[/code] — "together a
## normalized hop fraction" — not as a single [code]hop_fraction[/code] field.
## The derivation therefore lives here, once, instead of in every visual that
## ramps. An explicit [code]hop_fraction[/code] still wins where present, so a
## coordinator (or a test) may hand over a literal it computed itself.
static func read_hop_fraction(entry: Variant, fallback: float) -> float:
	var explicit: float = read_float(entry, &"hop_fraction", -1.0)
	if explicit >= 0.0:
		return clampf(explicit, 0.0, 1.0)
	var count: float = read_float(entry, &"beat_count", -1.0)
	if count < 0.0:
		return fallback
	# A single wave has no ramp to walk, so it sits at the near end rather than
	# dividing by zero and landing on the far one.
	var span: float = maxf(count - 1.0, 1.0)
	return clampf(read_float(entry, &"beat_index", 0.0) / span, 0.0, 1.0)
