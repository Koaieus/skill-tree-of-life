@tool
class_name DotAddon
extends SkillNodeAddon

## A damage-over-time addon (#951, ADR 0023): ONE script, one `.tscn` per
## status — `toxin_addon.tscn` is the poison instance; corruption / curse /
## wither are `.tscn`-only siblings. "Toxin" is the scene's name, not a class.
##
## Two faces of one item:
## - Melee: on copy-onto-blade the vertex built from THIS carrier applies
##   [member status_def] at [member status_power] stacks on every contact it
##   lands — that vertex only, never the whole blade. Vertex damage is
##   untouched (owner: "damage untouched, status only"); potency and
##   resistance scale the stacks at land time exactly as an arrow's do.
## - Ranged: the carrier's owner gains poison arrows — authored as
##   [member SkillNodeAddon.entity_modifiers] in the `.tscn`, nothing here.

## The status the toxic vertex applies on contact.
@export var status_def: StatusDef
## Stacks per landed contact, before the attacker's potency and the target's
## resistance fold in at land ([method StatusInstance.land_on]).
@export var status_power: float = 1.0


func apply_to_blade(state: BladeState, particle_idx: int) -> void:
	if status_def == null:
		return
	state.vertex_status_def[particle_idx] = status_def
	state.vertex_status_power[particle_idx] = status_power
