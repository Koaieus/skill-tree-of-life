@tool
class_name SpikeRingAddon
extends SkillNodeAddon

## [b]The real addon is the scene[/b], [code]spike_ring_addon.tscn[/code]: the
## authored [code]local_modifiers[/code], icon and its [SpikeRingVisual] child
## live there. This script only adds what a scene can't author: the
## stake-scaled grants below.
##
## Offensive sharpness: contributes to the carrier's node-local `blade_damage`
## stat via the base class's authored `local_modifiers` array (see the
## addon's .tscn). Both blade-build paths read per-vertex damage via
## SkillNode.get_local_value(&"blade_damage"), which merges this node-local
## modifier with the owner's board — so a swept spiked node deals
## base + spike, and preview matches commit. See docs/design/skill_node_addons.md.
##
## Defensive `spikes` / `spike_regen` pop budget (#778): the ONLY source of
## either stat is this addon — an unspiked node holds `spikes` 0 at any stake
## level (there is no base grant anywhere else). Also raises the carrier's own
## `blunting` from the def's default 1 to 2, since a spiked node's blade
## vertex is itself reinforced.
##
## These three are computed, not authored on `local_modifiers` in the .tscn,
## because two of them scale with `stake_level` — see [method get_local_modifiers].
##
## Defensive side (blade-vs-blade collision, spike-attacks-incoming-blade
## structure) is explicitly out-of-scope per docs/design/skill_node_addons.md
## — collision model is open and "do not implement until specified".

## `spikes` cap grant, ADD_BASE with a [LinearFormula] reading the carrier's
## own `stake_level` (the N in the M/N dial, i.e. [member SkillNode.stake_level]
## — a bare token, deliberately not `stake_level__current`: it is the STAKE
## that scales the grant, not the fill). Coefficient 2 — a fully-staked (3)
## spiked node holds spikes cap 6, per the issue's own worked example.
## Built once and cached: [method SkillNodeAddon.get_local_modifiers]'s
## contract requires the SAME instance across calls (SkillNode reclaims by
## identity on remove).
var _spikes_modifier: StatModifier

## `spike_regen` grant, same shape as [member _spikes_modifier] but
## coefficient 1 — a stake-3 node recovers spike_regen 3 per turn.
var _spike_regen_modifier: StatModifier

## `blunting` grant — flat +1 ADD_BASE, no formula: the def's base is 1, this
## addon raises a spiked attacking vertex to 2. Not stake-scaled (#778 —
## "blunting ships with default 1, 2 on a spiked vertex, nothing else").
var _blunting_modifier: StatModifier


## Lazily builds and caches the three synthesized modifiers above. Idempotent
## — subsequent calls are no-ops once [member _spikes_modifier] exists.
func _ensure_synthesized_modifiers() -> void:
	if _spikes_modifier != null:
		return
	var spikes_formula := LinearFormula.new()
	spikes_formula.source_stat_id = &"stake_level"
	spikes_formula.per_phrase = "stake level"
	_spikes_modifier = StatModifier.new()
	_spikes_modifier.stat_id = &"spikes"
	_spikes_modifier.operation = StatModifier.Operation.ADD_BASE
	_spikes_modifier.value = 2.0
	_spikes_modifier.formula = spikes_formula

	var regen_formula := LinearFormula.new()
	regen_formula.source_stat_id = &"stake_level"
	regen_formula.per_phrase = "stake level"
	_spike_regen_modifier = StatModifier.new()
	_spike_regen_modifier.stat_id = &"spike_regen"
	_spike_regen_modifier.operation = StatModifier.Operation.ADD_BASE
	_spike_regen_modifier.value = 1.0
	_spike_regen_modifier.formula = regen_formula

	_blunting_modifier = StatModifier.new()
	_blunting_modifier.stat_id = &"blunting"
	_blunting_modifier.operation = StatModifier.Operation.ADD_BASE
	_blunting_modifier.value = 1.0


## Overrides the base class default (the authored [member local_modifiers]
## array, which still carries the offensive `blade_damage` bonuses from the
## .tscn) to append the three computed grants above.
func get_local_modifiers() -> Array[StatModifier]:
	_ensure_synthesized_modifiers()
	var out := local_modifiers.duplicate()
	out.append(_spikes_modifier)
	out.append(_spike_regen_modifier)
	out.append(_blunting_modifier)
	return out


# ─── Tooltip ───────────────────────────────────────────────────────────────

func get_tooltip_title() -> String:
	return "Spikes"

