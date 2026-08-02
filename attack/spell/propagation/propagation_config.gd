@tool
class_name PropagationConfig
extends Resource

## Composition of the three small interfaces that drive a spell's walk
## ([PropagationFilter] / [PropagationStep] / [IncidentReducer]) plus the
## scalar knobs every spell needs. [SpellDef.propagation] points at one of
## these.
##
## Design rationale: filter / step / reducer are orthogonal axes — mixing
## stock subclasses produces a combinatorial space of spell behaviours
## without subclassing. See [code]docs/domain/spell-propagation.md[/code]
## for the full pipeline and [code]docs/design/spells.md[/code] for the
## spell catalogue authored against this shape.

## Decides which neighbour candidates are eligible at each step. Null = no
## filtering (every neighbour passes — useful for tests).
@export var filter: PropagationFilter = null

## Mints the outgoing [CastSpell] copies from the filtered candidate list.
## Null = the spell does not propagate (single-target).
@export var step: PropagationStep = null

## Resolves ≥1 simultaneous incidents at the same node in the same wave.
## Null = first-wins (no merging, just take incidents[0]).
@export var reducer: IncidentReducer = null

## Max hops from the seed (0 = seed only, no propagation).
@export var max_hops: int = 0

## Hard cap on how many times this cast can land on the SAME node. 1 = the
## default "never revisit" (read by [MaxVisitsFilter]). INT_MAX (or any
## large value) effectively uncaps it — Resonator territory.
@export var max_visits_per_node: int = 1

## Per-hop damage ramp applied by [PropagationStep._propagate_to]. Null = no
## scaling (damage carried verbatim — the historical
## [code]damage_multiplier_per_hop = 1.0[/code] default). Plug a stock
## [HopDamage] subclass here: [MultiplyRamp] (falloff / rampup),
## [AddRamp] (flat add per hop), [AffineRamp] (both), [ExpressionRamp]
## (escape hatch). See #351.
@export var hop_damage: HopDamage = null

## One-time multiplier baked into the SEED hit's damage. 0.25 = Crunch's
## "1/4 to initial then ramp"; 1.0 = the seed takes full base damage.
@export var seed_damage_fraction: float = 1.0


func get_description() -> String:
	var parts: PackedStringArray = []
	if step != null:
		parts.append(step.get_description())
	if filter != null:
		var fd := filter.get_description()
		if fd != "":
			parts.append(fd)
	if reducer != null:
		var rd := reducer.get_description()
		if rd != "":
			parts.append(rd)
	parts.append("Up to %d hop%s." % [max_hops, "" if max_hops == 1 else "s"])
	return " ".join(parts)
