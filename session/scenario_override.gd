@tool
class_name ScenarioOverride
extends Resource

## A leaf-addressed, by-value patch onto a duplicated [GraphProcgenConfig]
## (#642 D14 — "Decision — the override encoder"). Not a module resource and
## not a stringly-typed [Dictionary]: a typed, inspector-authorable Resource
## carrying exactly one (path, scalar) pair.
##
## [member target] is a property path into the DUPLICATED [GraphProcgenConfig],
## in Godot's subname form: `"content:budget_policy:base_min"`. Colons, not
## slashes. [member value] is always a primitive/scalar — never a Resource,
## never a path — which is what makes an in-memory "Custom" override survive
## [method RunConfig.to_dict] with no `resource_path` involved anywhere (#642
## acceptance 3, #597 D4's named failure mode made unreachable by construction).
##
## [b]D15 hardening[/b] (comment "Hardening D14", 2026-08-27): `set_indexed`
## fails SILENTLY three ways — a typed-array target with an untyped payload,
## a wrong-type scalar, and a lossy float-into-int truncation. [method merge_onto]
## closes all three by construction: a [member target] must resolve to a
## SCALAR leaf (int/float/bool/String/StringName — arrays, dictionaries and
## objects are rejected), and the incoming [member value] is type-checked
## against that leaf's OWN declared type (read via `get_property_list()`,
## never assumed) before anything is written. A rejection always
## `push_warning`s naming the target and leaves the preset byte-for-byte
## unchanged — never a silent no-op.

## Property path into the duplicated [GraphProcgenConfig] this override
## patches, in subname form. Empty is legal on a freshly-authored resource
## and is rejected (with a warning, not a crash) at merge time.
@export var target: String = ""
## The scalar value to write at [member target]. Never a Resource and never
## a path — see the class doc's #597 D4 note.
@export var value: Variant = null

## Fields [GraphProcgenConfig] stamps at runtime from the [ParticipantRoster]
## rather than authoring — a second source of truth against the roster if an
## override could reach them (#642 acceptance 9, moved here from #641 where
## the equivalent assertion was vacuous).
const _RUNTIME_STAMPED_FIELDS := [
	"seed", "camp_sizes", "n_random_starters", "viability_radius",
]

## The only [Variant.Type]s D15 allows a target to resolve to. Everything
## else (TYPE_ARRAY, TYPE_DICTIONARY, TYPE_OBJECT, TYPE_NIL for an
## unresolved path) is rejected before any write is attempted.
const _SCALAR_TYPES := [
	TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME,
]


## Wire form (#642 acceptance 3) — plain primitives, exactly [method Participant.to_dict]'s
## shape. `value` rides as whatever primitive it already is; Godot's own
## dict/array wire codec (`var_to_bytes`) preserves int-vs-float and typed
## arrays across the hop, so nothing extra is needed here.
func to_dict() -> Dictionary:
	return {"target": target, "value": value}


static func from_dict(d: Dictionary) -> ScenarioOverride:
	var o := ScenarioOverride.new()
	o.target = String(d.get("target", ""))
	o.value = d.get("value")
	return o


## Structural warnings checkable in isolation (an empty target patches
## nothing). Resolving a target against a real preset needs the preset in
## hand — that half lives in [method merge_onto], which is what a merge
## actually runs and what acceptance 8/11 assert against.
func _get_configuration_warnings() -> PackedStringArray:
	var out: PackedStringArray = []
	if target.is_empty():
		out.append("ScenarioOverride: target is empty — this override patches nothing.")
	return out


## Duplicates [param preset] and applies every entry in [param overrides] onto
## the copy (#642 D14) — the module-ref-swap-on-a-duplicate this issue is
## named for, generalised to a leaf write. The authored [param preset] and
## every module it references are NEVER mutated (#642 acceptance 4): only a
## module actually touched by an override is given its own private
## `duplicate(true)` copy, and only once per merge, so two overrides into the
## same module compose onto the SAME copy rather than each discarding the
## other's write.
static func merge_onto(preset: GraphProcgenConfig, overrides: Array[ScenarioOverride]) -> GraphProcgenConfig:
	var cfg: GraphProcgenConfig = preset.duplicate(true)
	var localized_modules: Dictionary = {}
	for o in overrides:
		_apply(cfg, o, localized_modules)
	return cfg


static func _apply(cfg: GraphProcgenConfig, o: ScenarioOverride, localized_modules: Dictionary) -> void:
	if o.target.is_empty():
		push_warning("ScenarioOverride: empty target, skipped")
		return
	if o.target in _RUNTIME_STAMPED_FIELDS:
		push_warning(
				"ScenarioOverride: '%s' is a runtime-stamped field derived from the "
				% o.target + "ParticipantRoster — overrides targeting it are rejected")
		return

	var resolved := _resolve_leaf_type(cfg, o.target)
	if resolved.is_empty():
		push_warning("ScenarioOverride: target '%s' does not resolve on the preset" % o.target)
		return
	var declared_type: int = resolved["type"]
	if not (declared_type in _SCALAR_TYPES):
		push_warning(
				"ScenarioOverride: target '%s' resolves to a non-scalar (Variant.Type %d) — "
				% [o.target, declared_type] + "rejected, never merged")
		return

	var coerced: Variant = _coerce(o.target, o.value, declared_type)
	if coerced == null:
		return  # _coerce already warned with the specific reason

	_localize_module(cfg, o.target, localized_modules)
	cfg.set_indexed(o.target, coerced)


## Resolves [param target]'s OWNER object (everything before the last colon)
## via the engine's own subname traversal, then reads the LEAF's declared
## type off that owner's `get_property_list()` (D15 point 2 — "the declared
## types ARE the schema"). Returns `{}` (unresolved) when the owner path
## doesn't resolve to an Object at all, or the leaf name isn't one of the
## owner's properties — both fold into the same "does not resolve" case
## (#642 acceptance 8).
static func _resolve_leaf_type(cfg: GraphProcgenConfig, target: String) -> Dictionary:
	var sep := target.rfind(":")
	var leaf: String
	var owner: Object
	if sep == -1:
		leaf = target
		owner = cfg
	else:
		leaf = target.substr(sep + 1)
		var owner_path := target.substr(0, sep)
		var owner_value: Variant = cfg.get_indexed(owner_path)
		if not (owner_value is Object):
			return {}
		owner = owner_value
	if leaf.is_empty():
		return {}
	for prop in owner.get_property_list():
		if prop.name == leaf:
			return {"type": prop.type}
	return {}


## Type-checks + coerces [param value] against a leaf's [param declared_type],
## returning `null` (after warning with the specific reason) when it can't be
## made to fit. An exact type match passes through unchanged; a float landing
## on an int leaf is EXPLICITLY rounded (never truncated) and warns iff that
## rounding is lossy (#642 acceptance 11.3) — everything else is a rejection
## (acceptance 11.2).
##
## [b]`null` is never a legitimate coerced value here[/b] — every type in
## [constant _SCALAR_TYPES] has a non-null default, so this is a safe
## success/failure sentinel.
static func _coerce(target: String, value: Variant, declared_type: int) -> Variant:
	var value_type := typeof(value)
	if value_type == declared_type:
		return value
	if declared_type == TYPE_INT and value_type == TYPE_FLOAT:
		var rounded := roundi(value)
		if not is_equal_approx(float(rounded), float(value)):
			push_warning(
					"ScenarioOverride: '%s' float value %s rounded to int %d (lossy)"
					% [target, value, rounded])
		return rounded
	if declared_type == TYPE_FLOAT and value_type == TYPE_INT:
		return float(value)
	push_warning(
			"ScenarioOverride: '%s' expects Variant.Type %d, got %d — rejected, never merged"
			% [target, declared_type, value_type])
	return null


## Gives the top-level module ref ([param target]'s first path segment —
## `topology`/`shape`/`starting`/`content`/`blockers`) its own private
## `duplicate(true)` copy, exactly once per merge. Each module is its own
## top-level `.tres` (an ExtResource from [GraphProcgenConfig]'s perspective),
## so [method GraphProcgenConfig.duplicate]`(true)` does NOT cross that
## boundary (`test_module_split.gd`'s acceptance-4 guard is the same trap) —
## writing through `set_indexed` without this step would corrupt the SAME
## cached module object every other loader of that preset shares. A target
## with no colon writes directly on `cfg` itself, which is already private
## (the top-level `preset.duplicate(true)` in [method merge_onto]), so it's a
## no-op there.
static func _localize_module(cfg: GraphProcgenConfig, target: String, localized_modules: Dictionary) -> void:
	var sep := target.find(":")
	if sep == -1:
		return
	var module_name := target.substr(0, sep)
	if localized_modules.has(module_name):
		return
	localized_modules[module_name] = true
	var current: Variant = cfg.get(module_name)
	if current is Resource:
		cfg.set(module_name, (current as Resource).duplicate(true))
