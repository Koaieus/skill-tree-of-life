@abstract
class_name VFXCoordinator
extends Node2D

## Plays the visual sequence for one action — an attack, a spell, anything
## that fires once and resolves. One subclass per "shape" of action:
## [RangedVolleyCoordinator] = N projectiles; future melee = phantom-blade
## swing; future magic = projectile hopping along edges.
##
## Coordinators are instantiated as world-space children of [AttackVFX]
## (the dispatcher). The dispatcher awaits [method play], then frees the
## coordinator. Implementations decide WHEN within their sequence to call
## the game-state mutation (e.g. [method SkillNode.take_damage]) —
## typically at the dramatic moment, so reactive VFX (the hit-flash on
## [signal SkillNode.damaged]) syncs automatically.


## Returns when the visual sequence is fully drained — i.e. every spawned
## child (projectile, swing, particle) has finished lingering and the
## dispatcher is safe to [method queue_free] this coordinator without
## visual pop. [param payload] is action-specific; concrete subclasses
## cast and validate.
@abstract func play(payload: Variant) -> void
