@tool
class_name DotAddon
extends SkillNodeAddon

## A damage-over-time addon (#951, ADR 0023): ONE script, one `.tscn` per
## status — `toxin_addon.tscn` is the poison instance; corruption / curse /
## wither are `.tscn`-only siblings. "Toxin" is the scene's name, not a class.
##
## Two faces of one item:
## - Melee: on copy-onto-blade the vertex built from THIS carrier runs
##   [member on_hit_effects] on every contact it lands — that vertex only,
##   never the whole blade. Vertex damage is untouched (owner: "damage
##   untouched, status only"); an [ApplyStatusEffect]'s potency and
##   resistance fold in at land time exactly as an arrow's do.
## - Ranged: the carrier's owner gains poison arrows — authored as
##   [member SkillNodeAddon.entity_modifiers] in the `.tscn`, nothing here.

## What the carrier's vertex does on every contact it lands — the one on-hit
## vocabulary blades share with spells and arrows (ADR 0044); usually one
## [ApplyStatusEffect]. Run in order, after the contact's damage hit, riding
## it ([member HitLanding.paired]). Spell-only riders ([SpellOnHitEffect])
## are dropped at load with one push_error; the stored array never holds one.
@export var on_hit_effects: Array[OnHitEffect] = []:
	set(value):
		var kept: Array[OnHitEffect] = []
		for effect in value:
			if effect is SpellOnHitEffect:
				push_error("%s: %s is spell-only; refused from on_hit_effects" % [scene_file_path, str(effect.resource_path)])
			else:
				kept.append(effect)
		on_hit_effects = kept


## Appends — never overwrites — so two DotAddons on one carrier both ride
## its contacts, in child order.
func apply_to_blade(state: BladeState, particle_idx: int) -> void:
	var riders: Array = state.vertex_on_hit[particle_idx]
	for effect in on_hit_effects:
		if effect != null:
			riders.append(effect)
