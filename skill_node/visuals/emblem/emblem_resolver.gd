class_name EmblemResolver
extends RefCounted
## Arbitrates a node's [EmblemSpec] contributions into what actually renders:
## the single winning CARVE (highest priority) plus every BLOOM (additive — they
## don't compete). Pure and scene-free: give it specs, get a [Resolution]. This
## is the layer that keeps SkillNode from needing to know about spells, loot, or
## keystones — sources contribute, this decides.

# Referenced via preload (not the bare class_name) so the resolver runs before
# the editor rebuilds the global class cache — see docs/domain/skillnode-emblem.md.
@warning_ignore("shadowed_global_identifier")
const EmblemSpec = preload("res://skill_node/visuals/emblem/emblem_spec.gd")


## The outcome of a resolve. [member carve] is the winning dent (or null for an
## empty dome); [member carve_ties] are the CARVEs tied at the winning priority
## (multiple spell grants → the combine strategy lives in the renderer, not
## here); [member blooms] are every BLOOM, drawn additively over the carve.
class Resolution:
	extends RefCounted
	var carve = null  # EmblemSpec or null
	var carve_ties: Array = []  # of EmblemSpec, tied at the winning priority
	var blooms: Array = []  # of EmblemSpec


static func resolve(contributions: Array) -> Resolution:
	var res := Resolution.new()
	var best := -1
	for spec in contributions:
		if spec == null:
			continue
		if spec.register == EmblemSpec.Register.BLOOM:
			res.blooms.append(spec)
			continue
		if spec.priority > best:
			best = spec.priority
			res.carve = spec
			res.carve_ties = [spec]
		elif spec.priority == best:
			res.carve_ties.append(spec)
	return res
