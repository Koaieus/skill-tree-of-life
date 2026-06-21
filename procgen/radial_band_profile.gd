@tool
class_name RadialBandProfile
extends WeightProfile

## Position-bucketed tag multipliers. Maps `ctx.position` → a band (inner /
## mid / outer by default) → per-tag multipliers, then multiplies those
## together for each matching tag on the entry.
##
## Designer-time shape:
##   center = Vector2.ZERO
##   outer_radius = 1000.0
##   band_boundaries = [0.33, 0.66]            # fractions of outer_radius
##   band_names = [&"inner", &"mid", &"outer"]
##   weights = {
##     &"outer": { &"rare": 4.0, &"mythic": 8.0, &"common": 0.6 },
##     &"inner": { &"common": 1.2 },
##   }
##
## A band NOT mentioned in `weights` contributes 1.0 (neutral). A tag NOT
## mentioned within its band's dict contributes 1.0.

@export var center: Vector2 = Vector2.ZERO
@export var outer_radius: float = 1000.0
## Fractions of `outer_radius`. With `[0.33, 0.66]` you get three bands:
## inner = [0, 0.33·R), mid = [0.33·R, 0.66·R), outer = [0.66·R, ∞).
## Boundaries must be strictly ascending.
@export var band_boundaries: PackedFloat32Array = PackedFloat32Array([0.33, 0.66])
## One name per band. `band_names.size()` must equal `band_boundaries.size() + 1`.
@export var band_names: Array[StringName] = [&"inner", &"mid", &"outer"]
## Per-band per-tag multipliers.
@export var weights: Dictionary = {}


func multiplier_for(entry: ModifierPoolEntry, context: WeightContext) -> float:
	if entry == null or context == null:
		return 1.0
	if band_names.is_empty() or outer_radius <= 0.0:
		return 1.0
	var band := _band_for(context.position)
	if band == &"":
		return 1.0
	var band_dict: Dictionary = weights.get(band, {})
	if band_dict.is_empty():
		return 1.0
	var m := 1.0
	for tag in entry.tags:
		if band_dict.has(tag):
			m *= float(band_dict[tag])
	return m


func _band_for(position: Vector2) -> StringName:
	var d := position.distance_to(center)
	var ratio := d / outer_radius
	for i in band_boundaries.size():
		if ratio < band_boundaries[i]:
			if i < band_names.size():
				return band_names[i]
			return &""
	return band_names.back() if not band_names.is_empty() else &""


func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	if band_names.size() != band_boundaries.size() + 1:
		out.append("band_names size (%d) must equal band_boundaries size + 1 (%d)." % [band_names.size(), band_boundaries.size() + 1])
	for i in band_boundaries.size() - 1:
		if band_boundaries[i + 1] <= band_boundaries[i]:
			out.append("band_boundaries must be strictly ascending; index %d ≥ %d." % [i, i + 1])
	var registry := TagRegistry.canonical()
	if registry != null:
		for band in weights.keys():
			var d: Dictionary = weights[band]
			var unknown := registry.unknown_tags(d.keys())
			for t in unknown:
				out.append("band '%s' references unknown tag: %s" % [String(band), String(t)])
	return out
