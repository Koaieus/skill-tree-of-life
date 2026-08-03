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

## How damage evolves per hop, applied by [PropagationStep._propagate_to].
## Null = no progression (damage carried verbatim). Plug a stock
## [HopDamageProgression] subclass here: [MultiplyProgression] (geometric
## falloff / rampup), [ScaledAddProgression] (arithmetic, a fraction of the
## seed per hop), [FlatAddProgression] (arithmetic, absolute — deliberately
## does not scale with the caster), [ExpressionProgression] (escape hatch).
## The class states whether the spell scales with the caster; see #274 / D-32.
@export var hop_damage: HopDamageProgression = null


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
