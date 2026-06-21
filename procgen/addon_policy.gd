@tool
class_name AddonPolicy
extends Resource

## Procgen v2 second-pass content config. After the per-node modifier roll
## finishes, each node has a `chance_per_node` probability of also rolling
## addons. Addons get their own budget axis so designers can tune "how many
## modifier slots" and "how often does this archetype get an addon"
## independently (see docs/domain/procgen-v2.md, "AddonPolicy").
##
## The weight pipeline shares its [WeightProfile] vocabulary with the modifier
## pass. A [CollisionProfile] won't help here (addons don't collide on
## stat_id), but [ArchetypeWeightProfile] and a future "AlreadyRolledProfile"
## are natural fits — e.g. "Spikes are more likely on STR-tagged nodes."
##
## The addon-pass [WeightContext] carries the modifier-pass output as
## `already_rolled` so profiles can react to what's already on the node.

@export_range(0.0, 1.0) var chance_per_node: float = 0.0
@export var addon_budget_min: int = 1
@export var addon_budget_max: int = 1
@export var pool: AddonPool
@export var weight_profiles: Array[Resource] = []
