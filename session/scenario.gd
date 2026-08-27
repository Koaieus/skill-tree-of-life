class_name Scenario
extends Resource

## What game are we playing (#597 D9), as opposed to [RunConfig] — "who is
## playing it, right now". Authored as a handful of `.tres` under
## `session/scenarios/`, pickable and shareable like any other resource;
## [member RunConfig.scenario] points at one rather than duplicating its
## choices into every run.
##
## The direction test that settles which type holds which field (#597's own
## framing): could a [Scenario] `.tres` sensibly carry a `participants` array?
## No — participants carry peer ids, picked colours, picked camps. That is
## lobby OUTPUT, never authored content.
##
## No mode field (#597 D11a) — [method LobbyScreen.resolve_mode] stays the sole
## mode authority, deriving it from the roster at press time. A [Scenario]
## cannot know in advance how many humans will end up sharing a camp.
##
## Extended by #638, which adds the victory-condition slot to this same class
## (moving [member RunConfig.victory_condition] here is explicitly NOT this
## unit's job — see #641's acceptance 8).

## The composed procgen shape this scenario generates (#349). A composed
## [GraphProcgenConfig] — five module refs plus a seed — never edited through
## this reference, only pointed at. Consumed by whichever level scene below
## generates the map (today, always `scenes/procgen_play_sandbox.gd`, the
## script `scenes/level.tscn` and its sandboxes share).
@export var preset: GraphProcgenConfig

## The level scene a run carrying this [Scenario] routes to (#584 D5). Read by
## `scenes/meta/meta_root.gd`'s START handler — moving the field off
## [RunConfig] without moving its reader would relocate #584 D5's smell
## instead of discharging it.
@export var level_scene: PackedScene
