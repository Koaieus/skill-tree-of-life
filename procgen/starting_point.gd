@tool
class_name StartingPoint
extends Resource

## Anchor position guaranteed to become a SkillNode in procgen. Seeded into
## the Poisson sampler before random points, so spacing respects it. The
## generator returns the SkillNodes that landed on these (in order) so the
## caller can wire them as entity cores or whatever the level needs.
##
## `id` is an optional label for the caller — e.g. "player_core",
## "enemy_spawn_1" — used to disambiguate when there are multiple anchors.

@export var position: Vector2 = Vector2.ZERO
@export var id: StringName = &""
