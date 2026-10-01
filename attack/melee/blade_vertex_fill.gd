class_name BladeVertexFill
extends RefCounted
## The one per-vertex fill a blade gets from its source [SkillNode]s: what a
## swing reads per vertex, then the addon dispatch. Both the plan's
## [method MeleeAttackPlan.build_blade_state] and the visual
## [method SkillBlade.build_from_skill_nodes] fill through this, so preview,
## AI scoring and the live swing cannot drift on a vertex's numbers.
##
## Contract: [param nodes] is index-aligned with the [BladeState] particles.
## Stats are read first, addons dispatched after, so an addon's
## [method SkillNodeAddon.apply_to_blade] sees the filled arrays.
## No per-EDGE fill: ADR 0005 — an edge carries no stats.

## The stats a swing reads per vertex, each a localized read (wielder base
## merged with node-local modifiers, e.g. a spike). Index-paired with
## [constant STATE_ARRAYS]; anything that lints "what a vertex reads" reads
## this list.
const VERTEX_STATS: Array[StringName] = [&"blade_damage", &"blunting"]
## The [BladeState] array each of [constant VERTEX_STATS] lands in.
const STATE_ARRAYS: Array[StringName] = [&"vertex_damage", &"vertex_blunting"]


func fill(state: BladeState, nodes: Array[SkillNode]) -> void:
	for k in VERTEX_STATS.size():
		# Packed arrays copy on read, so the column is built whole and set.
		var column := PackedFloat32Array()
		column.resize(nodes.size())
		for i in nodes.size():
			column[i] = nodes[i].get_local_value(VERTEX_STATS[k])
		state.set(STATE_ARRAYS[k], column)
	for i in nodes.size():
		for addon in nodes[i].get_addons():
			addon.apply_to_blade(state, i)
