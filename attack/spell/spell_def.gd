@tool
class_name SpellDef
extends Resource

## Authored spell data — identity, cost, propagation strategy, on-hit effects,
## and the VFX coordinator scene. The "what it does" half is composition:
## pick a [SpellPropagation] subclass to define the walk + damage transform,
## and an array of [OnHitEffect] for what happens per node (damage is just
## the default first entry).

@export var name: String
@export_multiline var description: String
## Spell-card iconography. Rendered in the spell picker (top, large) and in
## tooltips. Optional — falls back to a glyph derived from the spell name.
@export var icon: Texture2D = null

## Required degree for [SkillNodes] to have (how many edges they have) before this spell may be fired
# 	could also opt for encoding this as an named (int)enum
@export var min_degree: int = 1

## Required mana to cast this spell
@export var mana_cost: int = 0

## Initial damage at the seed target. Multiplied at seed time by
## [member SpellPropagation.seed_damage_fraction], then at each propagation
## step by [member SpellPropagation.damage_multiplier_per_hop].
@export var base_damage: float = 0.0

## How this spell propagates from the seed target. [NoPropagation] = single-
## target; [AllNeighboursPropagation] = BFS fan-out (Lightning / Crunch / Flood).
@export var propagation: SpellPropagation = null

## What happens at every node the spell lands on, run in order. Damage is
## the standard first entry via [DamageEffect].
@export var on_hit_effects: Array[OnHitEffect] = []

## The visual coordinator scene the battle layer plays once resolution
## produces an outcome. Scene root must be a [VFXCoordinator] subclass.
@export var vfx_coordinator_scene: PackedScene = null

## How this spell's target is gathered + what counts as valid. The kind
## drives input dispatch (NODE click vs. world click); the predicates drive
## valid-target enumeration for highlight + AI.
@export var targeting: Targeting


func validate(_plan: MagicAttackPlan) -> Array[String]:
	var errors: Array[String] = []
	if targeting == null:
		errors.append(&"Spell has no targeting set")
	if propagation == null:
		errors.append(&"Spell has no propagation set")
	if on_hit_effects.is_empty():
		errors.append(&"Spell has no on-hit effects")
	return errors


func _to_string() -> String:
	return "<SpellDef %s (%d mana)>" % [name, mana_cost]
