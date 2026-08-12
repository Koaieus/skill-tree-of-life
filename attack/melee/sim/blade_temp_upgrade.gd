class_name BladeTempUpgrade
extends RefCounted

## Plan-local, this-swing-only Clamp/Spikes upgrades (#406) — spent from the
## same `blade_size` budget as blade-member selection, never a real attached
## [SkillNodeAddon]. Applied into a [BladeState] from a
## `Dictionary[SkillNode, StringName]` (node -> &"clamp" | &"spike"), shared
## by both [method MeleeAttackPlan.build_blade_state] (resolve) and
## [method SkillBlade.build_from_skill_nodes] (preview) so the two stay in
## parity by construction rather than by duplicated geometry — the drift
## #405 fixed.

const CLAMP: StringName = &"clamp"
const SPIKE: StringName = &"spike"

## Flat blade_size cost per upgrade type (original issue sketch, #406).
const COST: Dictionary = {
	CLAMP: 1,
	SPIKE: 2,
}

const _SPIKE_SCENE := preload("res://skill_node/addons/spike_ring_addon.tscn")

## Lazily-resolved, process-lifetime cache of the procgen SpikeRingAddon's
## authored blade_damage bonus — resolved once (a scene instantiate is not
## free at SkillNode/blade scale, see .claude/rules/skill-node-scale.md),
## never per apply() call, even though apply() runs every preview rebuild.
static var _spike_damage_bonus: float = -1.0


## Dispatch every entry in `upgrades` against `state`, using `skill_nodes`'
## array order to resolve each node's particle index. Call after vertex_damage
## is populated and after real-addon dispatch, so a temp upgrade layers on top
## the same way a real one would.
static func apply(
		state: BladeState,
		skill_nodes: Array[SkillNode],
		upgrades: Dictionary) -> void:
	if upgrades.is_empty():
		return
	for i in skill_nodes.size():
		var upgrade: StringName = upgrades.get(skill_nodes[i], &"")
		match upgrade:
			CLAMP:
				_apply_clamp(state, i)
			SPIKE:
				_apply_spike(state, i)


## Reuses ClampAddon's own weld-brace geometry (the static twin of its
## apply_to_blade instance method) so temp-Clamp produces identical
## constraints to a real one, by construction — no per-call allocation.
static func _apply_clamp(state: BladeState, particle_idx: int) -> void:
	ClampAddon.append_weld_braces(state, particle_idx)


## Reuses the procgen SpikeRingAddon's own authored blade_damage bonus (single
## source of truth for the magnitude — see .claude/rules/stat-knobs-and-bins.md)
## rather than a hardcoded literal. Spike carries no apply_to_blade hook (its
## damage rides local_modifiers through the stat board instead), so a temp
## Spike — never attached, never stat-board-merged — adds the same flat amount
## straight onto the already-localized vertex_damage.
static func _apply_spike(state: BladeState, particle_idx: int) -> void:
	if _spike_damage_bonus < 0.0:
		var spike := _SPIKE_SCENE.instantiate() as SpikeRingAddon
		var bonus := 0.0
		for mod in spike.local_modifiers:
			if mod.stat_id == &"blade_damage":
				bonus += mod.value
		spike.free()
		_spike_damage_bonus = bonus
	state.vertex_damage[particle_idx] += _spike_damage_bonus
