@tool
@abstract
class_name HopDamageProgression
extends Resource

## How a spell's damage evolves from hop to hop — plugs into
## [member PropagationConfig.hop_damage]. Called once per propagation step
## with the parent's damage, the cast's seed damage and the parent's
## hop_index; returns the child's damage.
##
## [b]Which layer this is[/b] (D-32). A cast's magnitude is
## [code]seed = spell_damage(source) × SpellDef.power[/code] — the caster's
## board stat times the spell's one absolute coefficient. This class owns the
## [i]shape[/i] of the walk, not the magnitude: a hop IS a re-cast
## ([method PropagationStep._propagate_to] mints a fresh [CastSpell] from its
## predecessor), so the per-hop term is re-cast efficiency.
##
## [b]A progression DECLARES whether it scales with the caster.[/b] Picking
## the class in the inspector answers that question up front — the reason
## these are four small resources instead of one class with three knobs:
## [codeblock]
## MultiplyProgression    damage × factor                       scales (geometric)
## ScaledAddProgression   damage + seed × seed_fraction_per_hop  scales (arithmetic)
## FlatAddProgression     damage + increment                     deliberately does NOT
## ExpressionProgression  authored expression                    author's choice
## [/codeblock]
## What is forbidden is an [i]undeclared[/i] absolute, not an absolute — see
## [FlatAddProgression], whose compression is the point.
##
## Mirrors the [code]StatFormula[/code] pattern in the stats system and the
## [PropagationFilter] / [IncidentReducer] / [CritCondition] pattern here.
## Renamed off "…Ramp" in #274; the old [code]HopDamage[/code] name collided
## with [code]Propagation…[/code] in conversation.


## [param damage] is the parent's damage (already progressed by prior hops),
## [param seed] the cast's seed damage (immutable across the walk), and
## [param hop_index] the parent's hop index (0 at the seed).
@abstract func apply(damage: float, seed_damage: float, hop_index: int) -> float


func get_description() -> String:
	return ""
