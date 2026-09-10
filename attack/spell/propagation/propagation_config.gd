@tool
class_name PropagationConfig
extends Resource

## Composition of the three small interfaces that drive a spell's walk
## ([PropagationFilter] / [PropagationSpread] / [IncidentReducer]) plus the
## scalar knobs every spell needs, and — since #852 — the [b]one[/b] place a
## child [CastSpell] is built ([method mint]). [SpellDef.propagation] points at
## one of these.
##
## Departure, per landing: filter [b]narrows[/b] → spread [b]selects[/b]
## picks → this config [b]mints[/b] one child per pick.
##
## Design rationale: filter / spread / reducer are orthogonal axes — mixing
## stock subclasses produces a combinatorial space of spell behaviours
## without subclassing. See [code]docs/domain/spell-propagation.md[/code]
## for the full pipeline and [code]docs/design/spells.md[/code] for the
## spell catalogue authored against this shape.

## Decides which neighbour candidates are eligible at each step. Null = no
## filtering (every neighbour passes — useful for tests).
@export var filter: PropagationFilter = null

## Selects which of the narrowed candidates the spell goes to, and with what
## share. Null = the spell does not propagate (single-target).
@export var spread: PropagationSpread = null

## Resolves ≥1 simultaneous incidents at the same node in the same wave.
## Null = first-wins (no merging, just take incidents[0]).
@export var reducer: IncidentReducer = null

## Max hops from the seed (0 = seed only, no propagation).
@export var max_hops: int = 0

## Hard cap on how many times this cast can land on the SAME node. 1 = the
## default "never revisit" — [SpellResolver] enforces this unconditionally,
## even with no filter set. INT_MAX (or any large value) effectively uncaps
## it — Resonator territory.
@export var max_visits_per_node: int = 1

## How damage evolves per hop, applied by [method mint].
## Null = no progression (damage carried verbatim). Plug a stock
## [HopDamageProgression] subclass here: [MultiplyProgression] (geometric
## falloff / rampup), [ScaledAddProgression] (arithmetic, a fraction of the
## seed per hop), [FlatAddProgression] (arithmetic, absolute — deliberately
## does not scale with the caster), [ExpressionProgression] (escape hatch).
## The class states whether the spell scales with the caster; see #274 / D-32.
@export var hop_damage: HopDamageProgression = null


## Build the child [CastSpell] for one [PropagationPick] — the hop IS a
## re-cast, and this is the only constructor of one. Damage is shaped by
## [member hop_damage] (a [HopDamageProgression] — null is identity, damage
## carried verbatim) and THEN multiplied by [member PropagationPick.share], so
## an authored ramp composes with a spread's split; hops_remaining decrements;
## hop_index advances; the lineage gains the destination (or is replaced by the
## pick's [member PropagationPick.lineage_override]). [member CastSpell.seed_damage]
## is copied verbatim so a seed-relative progression sees the cast's original
## magnitude. Every other pick field is copied onto the child as-is: the spread
## decided it, the mint does not reinterpret it.
func mint(payload: CastSpell, pick: PropagationPick) -> CastSpell:
	var next := CastSpell.new()
	next.seed_node = payload.seed_node
	next.current_node = pick.node
	next.predecessor = payload.current_node
	next.source = payload.source
	next.seed_damage = payload.seed_damage
	var progressed := payload.damage
	if hop_damage != null:
		progressed = hop_damage.apply(payload.damage, payload.seed_damage, payload.hop_index)
	next.damage = progressed * pick.share
	next.hops_remaining = payload.hops_remaining - 1
	next.hop_index = payload.hop_index + 1
	if pick.lineage_override.is_empty():
		next.visited = payload.visited.duplicate()
		next.visited.append(pick.node)
	else:
		next.visited = pick.lineage_override
	next.caster = payload.caster
	next.graph = payload.graph
	next.rng = payload.rng
	# The pick's stamps, verbatim.
	next.arrival_share = pick.share
	next.arrival_bearing = pick.arrival_bearing
	next.turn_sign = pick.turn_sign
	next.closed_cycle = pick.closed_cycle
	next.came_from = pick.came_from
	return next


## Player-facing "Then" line for [SpellTooltip] (#764). A null [member spread]
## or a zero-hop config never leaves the seed, and every sense that matters
## here reads as "single target" rather than as a spread describer built for
## the propagating case saying "0 hops" — owned here, not in UI code, so
## every caller (tooltip today, #853's catalogue tomorrow) gets the same
## answer without re-deriving the collapse.
func get_description() -> String:
	if spread == null or max_hops <= 0:
		return "Single target."
	var parts: PackedStringArray = []
	parts.append(spread.get_description())
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
