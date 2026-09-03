@tool
class_name ScenarioOverride
extends Resource

## A leaf-addressed, by-value patch onto a duplicated [Scenario] (#642 D14 —
## "Decision — the override encoder", rooted one level up onto [Scenario]
## itself by #742). Not a module resource and not a stringly-typed
## [Dictionary]: a typed, inspector-authorable Resource carrying exactly one
## (path, value) pair.
##
## [b]Rooted at [Scenario], not at [member Scenario.preset][/b] (#742). A
## [Scenario] is itself just another Resource with ExtResource-typed fields —
## `preset` is one of them, `victory_condition` another — so there is no need
## for a second override list to reach the latter: a preset-targeting override
## just gains a `preset:` prefix (`"content:budget_policy:base_min"` ->
## `"preset:content:budget_policy:base_min"`), while `"victory_condition"`
## needs none. Same walk, same [method _resolve_leaf_type] -> class-check ->
## `set_indexed` machinery, no routing branch to distrust.
##
## [member target] is a property path into the DUPLICATED [Scenario], in
## Godot's subname form: `"preset:content:budget_policy:base_min"`. Colons,
## not slashes. [member value] is a primitive/scalar for a scalar leaf, or a
## resource PATH (a String) for a Resource-typed leaf (#742 — see
## [method _coerce_resource]) — never an embedded object, which is what makes
## an in-memory "Custom" override survive [method RunConfig.to_dict] with no
## `resource_path` involved anywhere (#642 acceptance 3, #597 D4's named
## failure mode made unreachable by construction).
##
## [b]D15 hardening[/b] (comment "Hardening D14", 2026-08-27): `set_indexed`
## fails SILENTLY three ways — a typed-array target with an untyped payload,
## a wrong-type scalar, and a lossy float-into-int truncation. [method merge_onto]
## closes all three by construction: a [member target] must resolve to a
## SCALAR leaf (int/float/bool/String/StringName) or a Resource-typed leaf
## (arrays and dictionaries are still rejected outright), and the incoming
## [member value] is type-checked against that leaf's OWN declared type (read
## via `get_property_list()`, never assumed) before anything is written. A
## rejection always `push_warning`s naming the target and leaves the scenario
## byte-for-byte unchanged — never a silent no-op.

## Property path into the duplicated [Scenario] this override patches, in
## subname form. Empty is legal on a freshly-authored resource and is
## rejected (with a warning, not a crash) at merge time.
@export var target: String = ""
## The value to write at [member target]: a scalar for a scalar leaf, or a
## resource path (String) for a Resource-typed leaf. Never an embedded
## Resource — see the class doc's #597 D4 note.
@export var value: Variant = null

## Fields the merged config carries that are stamped at runtime from the
## [ParticipantRoster] rather than authored — a second source of truth
## against the roster if an override could reach them (#642 acceptance 9,
## moved here from #641 where the equivalent assertion was vacuous). Rooted
## the same way every other target is since #742 — both live on the PRESET,
## not the Scenario itself.
const _RUNTIME_STAMPED_FIELDS := [
	"preset:seed", "preset:camp_sizes",
]

## The [Variant.Type]s D15 allows a target to resolve to WITHOUT going through
## the Resource-leaf path — everything else that isn't `TYPE_OBJECT` either
## (`TYPE_ARRAY`, `TYPE_DICTIONARY`, `TYPE_NIL` for an unresolved path) is
## rejected before any write is attempted.
const _SCALAR_TYPES := [
	TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME,
]


## Wire form (#642 acceptance 3) — plain primitives, exactly [method Participant.to_dict]'s
## shape. `value` rides as whatever primitive it already is; Godot's own
## dict/array wire codec (`var_to_bytes`) preserves int-vs-float and typed
## arrays across the hop, so nothing extra is needed here. A Resource-leaf
## override's `value` is already a plain String (the asset path), so this
## needs no branch for #742's object-leaf swap either.
func to_dict() -> Dictionary:
	return {"target": target, "value": value}


static func from_dict(d: Dictionary) -> ScenarioOverride:
	var o := ScenarioOverride.new()
	o.target = String(d.get("target", ""))
	o.value = d.get("value")
	return o


## Structural warnings checkable in isolation (an empty target patches
## nothing). Resolving a target against a real scenario needs the scenario in
## hand — that half lives in [method merge_onto], which is what a merge
## actually runs and what acceptance 8/11 assert against.
func _get_configuration_warnings() -> PackedStringArray:
	var out: PackedStringArray = []
	if target.is_empty():
		out.append("ScenarioOverride: target is empty — this override patches nothing.")
	return out


## Duplicates [param scenario] and applies every entry in [param overrides] onto
## the copy (#642 D14, rooted at [Scenario] since #742) — the
## module-ref-swap-on-a-duplicate this issue is named for, generalised to a
## leaf write. The authored [param scenario] and every module it references
## are NEVER mutated (#642 acceptance 4): only a module actually touched by an
## override is given its own private `duplicate(true)` copy, and only once per
## merge, so two overrides into the same module compose onto the SAME copy
## rather than each discarding the other's write.
static func merge_onto(scenario: Scenario, overrides: Array[ScenarioOverride]) -> Scenario:
	var out: Scenario = scenario.duplicate(true)
	var localized_modules: Dictionary = {}
	for o in overrides:
		_apply(out, o, localized_modules)
	return out


static func _apply(root: Resource, o: ScenarioOverride, localized_modules: Dictionary) -> void:
	if o.target.is_empty():
		push_warning("ScenarioOverride: empty target, skipped")
		return
	if o.target in _RUNTIME_STAMPED_FIELDS:
		push_warning(
				"ScenarioOverride: '%s' is a runtime-stamped field derived from the "
				% o.target + "ParticipantRoster — overrides targeting it are rejected")
		return

	var resolved := _resolve_leaf_type(root, o.target)
	if resolved.is_empty():
		push_warning("ScenarioOverride: target '%s' does not resolve on the scenario" % o.target)
		return
	var declared_type: int = resolved["type"]

	var coerced: Variant
	if declared_type in _SCALAR_TYPES:
		coerced = _coerce(o.target, o.value, declared_type)
		if coerced == null:
			return  # _coerce already warned with the specific reason
	elif declared_type == TYPE_OBJECT:
		coerced = _coerce_resource(o.target, o.value, String(resolved.get("hint_string", "")))
		if coerced == null:
			return  # _coerce_resource already warned with the specific reason
	else:
		push_warning(
				"ScenarioOverride: target '%s' resolves to a non-scalar, non-Resource (Variant.Type %d) — "
				% [o.target, declared_type] + "rejected, never merged")
		return

	_localize_module(root, o.target, localized_modules)
	root.set_indexed(o.target, coerced)


## Resolves [param target]'s OWNER object (everything before the last colon)
## via the engine's own subname traversal, then reads the LEAF's declared
## type off that owner's `get_property_list()` (D15 point 2 — "the declared
## types ARE the schema"). Returns `{}` (unresolved) when the owner path
## doesn't resolve to an Object at all, or the leaf name isn't one of the
## owner's properties — both fold into the same "does not resolve" case
## (#642 acceptance 8). `hint_string` rides along for a `TYPE_OBJECT` leaf —
## a `@export var x: SomeResourceType` property carries its class name there
## (#742), which is what lets [method _coerce_resource] class-check a swap.
static func _resolve_leaf_type(root: Resource, target: String) -> Dictionary:
	var sep := target.rfind(":")
	var leaf: String
	var owner: Object
	if sep == -1:
		leaf = target
		owner = root
	else:
		leaf = target.substr(sep + 1)
		var owner_path := target.substr(0, sep)
		var owner_value: Variant = root.get_indexed(owner_path)
		if not (owner_value is Object):
			return {}
		owner = owner_value
	if leaf.is_empty():
		return {}
	for prop in owner.get_property_list():
		if prop.name == leaf:
			return {"type": prop.type, "hint_string": prop.hint_string}
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


## D15 point 2, extended to an object-typed leaf (#742): a leaf whose DECLARED
## type is a Resource subclass accepts a resource PATH (a String) — never an
## embedded object off the wire, the same guarantee the seed already gives the
## map. `load()`s it, class-checks the loaded resource against the leaf's
## declared class ([method _is_resource_of_class] — a leaf declared
## `StarterPlacement` must accept a `CenterCoreStarters` or
## `CampAnnulusStarters`, not only an exact-type match), then hands back a
## PRIVATE `duplicate(true)` copy — the merge never installs the cached
## `load()` instance, so two runs picking the same asset never share one live
## object.
static func _coerce_resource(target: String, value: Variant, class_hint: String) -> Resource:
	var value_type := typeof(value)
	if value_type != TYPE_STRING and value_type != TYPE_STRING_NAME:
		push_warning(
				"ScenarioOverride: '%s' resolves to a Resource leaf — value must be a resource path "
				% target + "(String), got Variant.Type %d — rejected, never merged" % value_type)
		return null
	var path := String(value)
	if not ResourceLoader.exists(path):
		push_warning(
				"ScenarioOverride: '%s' value '%s' does not resolve to an existing resource — "
				% [target, path] + "rejected, never merged")
		return null
	var loaded: Resource = load(path)
	if loaded == null:
		push_warning("ScenarioOverride: '%s' failed to load '%s' — rejected, never merged" % [target, path])
		return null
	if not class_hint.is_empty() and not _is_resource_of_class(loaded, class_hint):
		push_warning(
				"ScenarioOverride: '%s' expects a %s, '%s' loaded a %s — rejected, never merged"
				% [target, class_hint, path, loaded.get_class()])
		return null
	return loaded.duplicate(true)


## Walks [param loaded]'s own script chain (never `get_class()`, which only
## ever reports the ENGINE base — "Resource" — for a GDScript-authored type)
## comparing global class names, so a leaf declared e.g. `StarterPlacement`
## accepts a subclass rather than only an exact-type match.
static func _is_resource_of_class(loaded: Resource, class_hint: String) -> bool:
	var scr: Script = loaded.get_script()
	while scr != null:
		if String(scr.get_global_name()) == class_hint:
			return true
		scr = scr.get_base_script()
	return false


## Gives every ExtResource-boundary segment [param target] crosses (everything
## before the leaf) its own private `duplicate(true)` copy, exactly once per
## merge (#742 widens this from a single fixed hop to a root-to-leaf walk).
## Each module is its own top-level `.tres` (an ExtResource from its owner's
## perspective — [Scenario]'s own `preset` is now one such hop, [GraphProcgenConfig]'s
## `topology`/`shape`/`starting`/`content`/`blockers` another), so plain
## `duplicate(true)` at the ROOT does NOT cross that boundary
## (`test_module_split.gd`'s acceptance-4 guard is the same trap) — writing
## through `set_indexed` without this step would corrupt the SAME cached
## object every other loader of that asset shares. A segment already localized
## by an earlier override in this merge is walked into rather than
## re-duplicated, so two overrides into the same module compose onto the SAME
## copy.
static func _localize_module(root: Resource, target: String, localized_modules: Dictionary) -> void:
	var segments := target.split(":")
	if segments.size() <= 1:
		return
	segments.remove_at(segments.size() - 1)
	var owner: Resource = root
	var path := ""
	for seg in segments:
		path = seg if path.is_empty() else "%s:%s" % [path, seg]
		var current: Variant = owner.get(seg)
		if not (current is Resource):
			return
		if localized_modules.has(path):
			owner = current
			continue
		localized_modules[path] = true
		var dup: Resource = (current as Resource).duplicate(true)
		owner.set(seg, dup)
		owner = dup
