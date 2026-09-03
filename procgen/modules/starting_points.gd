@tool
class_name GraphProcgenStartingPoints
extends Resource

## Starting points module (#349). The AUTHORED half of starter arrangement —
## the manual anchor list plus the random-starter and camp-placement knobs.
## Save as its own top-level `.tres` under `procgen/modules/<preset>/` and
## reference it by path from [GraphProcgenConfig.starting] — never embed it
## as a SubResource (#349 D3).
##
## `camp_sizes` is NOT here — it is runtime-stamped by the level from the
## roster, not authored, and lives on [GraphProcgenConfig] itself under its
## Runtime export group (#349 D4). Putting a roster-derived count in an
## authored module `.tres` would make it a second source of truth against the
## roster.

## Anchor points that MUST become skill nodes. Seeded into the Poisson
## sampler before random points, so they're guaranteed to land and the rest
## of the graph respects their spacing. Read only when [member starter_placement]
## is unset — a preset authoring one (every shipped preset does, since #742)
## replaces the starter list wholesale instead, and this array goes unread.
## After generation, [GraphProcgen.generate] returns the SkillNodes that
## landed on these (in order) so the caller can wire them as cores.
@export var starting_points: Array[StartingPoint] = []

@export_subgroup("Random starters")
## Generated `StartingPoint.id`s use this prefix plus an index — e.g.
## "enemy_0", "enemy_1". Read only alongside [member starting_points] on the
## no-[member starter_placement] path — the level never places a random
## anchor on that path any more (#742 lifted the random fill into
## [CenterCoreStarters]), so this is authored purely as a manual-list label
## today and has no live reader.
@export var random_starter_id_prefix: StringName = &"enemy"
## Bounded retry per random anchor. Threaded into
## [method StarterPlacement.plan]'s widened `max_tries` param (#742) — read by
## whichever [member starter_placement] a preset authors, e.g.
## [CenterCoreStarters]'s rejection-sampled fill.
@export var random_starter_max_tries: int = 200

@export_subgroup("Camp placement")
## Camp-relative starter placement (#551, #742). Unset (the default) means
## [member starting_points] drives the starter list verbatim, with no random
## fill. When set, [GraphProcgen.generate] REPLACES the manual list wholesale
## with `starter_placement.plan(camp_sizes, resolved_radius, min_dist, rng,
## shape_mask, random_starter_max_tries)` instead of assembling it from
## [member starting_points] — every shipped preset authors one:
## [CampAnnulusStarters] for a camp-relative annulus, [CenterCoreStarters] for
## a single centred human plus a random AI fill.
@export var starter_placement: StarterPlacement
