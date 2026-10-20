@tool
class_name PropagationConfig
extends Resource

## Composition of the three small interfaces that drive a spell's walk
## ([PropagationFilter] / [PropagationSpread] / [IncidentReducer]) plus the
## scalar knobs every spell needs, and — since #852 — the [b]one[/b] place a
## child [CastSpell] is built ([method mint]). [SpellDef.propagation] points at
## one of these.
##
## Departure, per landing: reach [b]proposes[/b] candidates (graph neighbours
## when [member reach] is null) → filter [b]narrows[/b] → spread [b]selects[/b]
## picks → this config [b]mints[/b] one child per pick.
##
## Design rationale: filter / spread / reducer are orthogonal axes — mixing
## stock subclasses produces a combinatorial space of spell behaviours
## without subclassing. See [code]docs/domain/spell-propagation.md[/code]
## for the full pipeline; the shipped spells authored against this shape
## are the [code].tres[/code] files in [code]attack/spell/defs/[/code].

## Decides which neighbour candidates are eligible at each step. Null = no
## filtering (every neighbour passes — useful for tests).
@export var filter: PropagationFilter = null

## Where a landing's wave CAN go, before the visit cap and [member filter]
## narrow it. Null = the landed node's graph neighbours. A reach may propose
## nodes with no edge to the landing (a euclidean blast); everything after it
## runs unchanged.
@export var reach: PropagationReach = null

## Selects which of the narrowed candidates the spell goes to, and with what
## share. Null = the spell does not propagate (single-target).
@export var spread: PropagationSpread = null

## Resolves ≥1 simultaneous incidents at the same node in the same wave.
## Null = first-wins (no merging, just take incidents[0]).
@export var reducer: IncidentReducer = null

## Max hops from the seed (0 = seed only, no propagation). `inf` = no hop
## limit: the walk runs until the filter or the never-revisit rule
## ([member max_visits_per_node] = 1) ends it — `inf - 1` stays `inf`, so no
## reader special-cases it except the ones that print a count. `inf` together
## with an uncapped [member max_visits_per_node] would walk effectively forever.
@export var max_hops: float = 0.0

## Hard cap on how many times this cast can land on the SAME node. 1 = the
## default "never revisit" — [SpellResolver] enforces this unconditionally,
## even with no filter set. INT_MAX (or any large value) effectively uncaps
## it — Resonator territory.
@export var max_visits_per_node: int = 1

## Repeat each landing: names a [CarriedScalar] in [member extensions] whose
## value at a landing is how many times that landing hits — each repeat its own
## payload copy, [member HitLanding.hit_key] and crit, landing in order, so a
## later repeat sees what an earlier one did to the node. Empty = one landing.
## Under [member IncidentReducer.hit_each_incident] the arrivals multiply: N
## incident arrivals × M repeats, each incident's repeats in order.
## A count of 0 lands nothing — author the scalar's [member CarriedScalar.min_value]
## so that hop is terminal. Departure reads the unrepeated landing, so an
## in-place [ScaleDamageEffect] scales each repeat but never the next hop.
@export var repeat_landings_by: StringName = &""

## How damage evolves per hop, applied by [method mint].
## Null = no progression (damage carried verbatim). Plug a stock
## [HopDamageProgression] subclass here: [MultiplyProgression] (geometric
## falloff / rampup), [ScaledAddProgression] (arithmetic, a fraction of the
## seed per hop), [FlatAddProgression] (arithmetic, absolute — deliberately
## does not scale with the caster), [ExpressionProgression] (escape hatch).
## The class states whether the spell scales with the caster; see #274 / D-32.
@export var hop_damage: HopDamageProgression = null

## How the status-stack weight ([member CastSpell.stack_weight]) evolves per
## hop, applied by [method mint] as [code]apply(weight, 1.0, hop_index)[/code]
## — the same classes as [member hop_damage], with a seed of 1, so
## [code]ScaledAddProgression(-1/3)[/code] lands 1, 2/3, 1/3 down a walk.
## Null = the weight is carried unchanged.
@export var hop_stacks: HopDamageProgression = null

## Spell-specific carried state: each template seeds, mints and merges one
## [PayloadState] in [member CastSpell.extras]. Empty for a spell that carries
## nothing beyond the universal fields.
@export var extensions: Array[PayloadExtension] = []


## Build the child [CastSpell] for one [PropagationPick] — the hop IS a
## re-cast. The child is [method CastSpell.derived] from [param payload], then
## advanced: damage is shaped by [member hop_damage] (null is identity) and
## THEN multiplied by [member PropagationPick.share], so an authored ramp
## composes with a spread's split; hops_remaining decrements; hop_index
## advances; the lineage gains the destination (or is replaced by the pick's
## [member PropagationPick.lineage_override]); [member CastSpell.arrival_share]
## records the pick's share.
##
## Then each of [member extensions] mints the child's state from the parent's
## (and copies whichever other pick stamps it carries, e.g. [CycloneFront]);
## a state marked [member PayloadState.terminal] ends the walk at the child.
##
## [param lctx] is the landing [param payload] just made — this wave has
## LANDED, so a world read through it sees this wave's stacks and damage.
func mint(payload: CastSpell, pick: PropagationPick, lctx: LandingContext) -> CastSpell:
	var next := CastSpell.derived(payload)
	next.current_node = pick.node
	next.predecessor = payload.current_node
	var progressed := payload.damage
	if hop_damage != null:
		progressed = hop_damage.apply(payload.damage, payload.seed_damage, payload.hop_index)
	next.damage = progressed * pick.share
	if hop_stacks != null:
		next.stack_weight = hop_stacks.apply(payload.stack_weight, 1.0, payload.hop_index)
	next.stack_weight *= pick.stack_share
	next.hops_remaining = 0.0 if pick.terminal else payload.hops_remaining - 1
	next.hop_index = payload.hop_index + 1
	if pick.lineage_override.is_empty():
		next.visited.append(pick.node)
	else:
		next.visited = pick.lineage_override
	# Per-arc telemetry, every spell: the share this arc was minted with.
	next.arrival_share = pick.share
	for ext in extensions:
		var state := ext.mint(payload.extra(ext.id), pick, lctx, payload.hop_index)
		next.extras.append(state)
		if state.terminal:
			next.hops_remaining = 0.0
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
	if reach != null:
		var rd := reach.get_description()
		if rd != "":
			parts.append(rd)
	if filter != null:
		var fd := filter.get_description()
		if fd != "":
			parts.append(fd)
	if reducer != null:
		var rd := reducer.get_description()
		if rd != "":
			parts.append(rd)
		var fd := reducer.fold_description()
		if fd != "" and not rd.contains(fd):
			parts.append(fd)
	if is_inf(max_hops):
		parts.append("No hop limit.")
	else:
		parts.append("Up to %d hop%s." % [max_hops, "" if max_hops == 1 else "s"])
	return " ".join(parts)
