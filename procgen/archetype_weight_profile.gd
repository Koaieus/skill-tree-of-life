@tool
class_name ArchetypeWeightProfile
extends WeightProfile

## Per-archetype tag multipliers. The canonical "STR-cluster boosts str-tagged
## entries ×3, depresses int ×0.2" profile.
##
## `weights` is keyed [archetype → [tag → mult]]. For each tag the entry
## carries that's listed under the active archetype, the per-tag multipliers
## are multiplied together to form the profile's overall contribution.
##
## A tag NOT mentioned in the archetype's dict contributes 1.0 (neutral).
## An archetype NOT mentioned in `weights` contributes 1.0 globally
## (everything passes through unchanged).
##
## Example author-time shape (inspector or .tres):
##   weights = {
##     &"red":  { &"str": 3.0, &"dex": 0.3, &"int": 0.2 },
##     &"blue": { &"int": 3.0, &"dex": 0.3, &"str": 0.2 },
##   }

@export var weights: Dictionary = {}


func multiplier_for(entry: ModifierPoolEntry, context: WeightContext) -> float:
	if entry == null or context == null:
		return 1.0
	var arch_dict: Dictionary = weights.get(context.archetype, {})
	if arch_dict.is_empty():
		return 1.0
	var m := 1.0
	for tag in entry.tags:
		if arch_dict.has(tag):
			m *= float(arch_dict[tag])
	return m


func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	var registry := TagRegistry.canonical()
	if registry == null:
		return out
	for arch in weights.keys():
		var d: Dictionary = weights[arch]
		var tags_here: Array = d.keys()
		var unknown := registry.unknown_tags(tags_here)
		for t in unknown:
			out.append("archetype '%s' references unknown tag: %s" % [String(arch), String(t)])
	return out
