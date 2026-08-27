@tool
class_name GraphProcgenStartingPoints
extends Resource

## Starting points module (#349). The AUTHORED half of starter arrangement —
## the manual anchor list plus the random-starter and camp-placement knobs.
## Save as its own top-level `.tres` under `procgen/modules/<preset>/` and
## reference it by path from [GraphProcgenConfig.starting] — never embed it
## as a SubResource (#349 D3).
##
## `n_random_starters`, `viability_radius` and `camp_sizes` are NOT here —
## they are runtime-stamped by the level from the roster, not authored, and
## live on [GraphProcgenConfig] itself under its Runtime export group
## (#349 D4). Putting a roster-derived count in an authored module `.tres`
## would make it a second source of truth against the roster.

## Anchor points that MUST become skill nodes. Seeded into the Poisson
## sampler before random points, so they're guaranteed to land and the rest
## of the graph respects their spacing. Default = single core at (0,0).
## After generation, [GraphProcgen.generate] returns the SkillNodes that
## landed on these (in order) so the caller can wire them as cores.
@export var starting_points: Array[StartingPoint] = []

@export_subgroup("Random starters")
## Generated `StartingPoint.id`s use this prefix plus an index — e.g.
## "enemy_0", "enemy_1". Inert if [member GraphProcgenConfig.n_random_starters] is 0.
@export var random_starter_id_prefix: StringName = &"enemy"
## Bounded retry per random anchor. Hit it without placing → warn and skip.
@export var random_starter_max_tries: int = 200

@export_subgroup("Camp placement")
## Camp-relative annulus placement (#551). Unset (the default) = today's
## behaviour — [member starting_points] + [member GraphProcgenConfig.n_random_starters]
## drive the starter list, unchanged, so `first_level.tres` and every existing
## test are untouched. When set, [GraphProcgen.generate] REPLACES the manual
## list with `starter_placement.plan(camp_sizes, resolved_radius, min_dist, rng)`
## instead of assembling it from [member starting_points].
@export var starter_placement: StarterPlacement
