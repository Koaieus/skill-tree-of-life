@tool
class_name AddonPolicy
extends Resource

## Procgen addon placement config. Independent of the stat-modifier budget:
## one pass after the per-node loop places `addons_per_100_nodes` addons per
## 100 nodes, each on a node drawn uniformly WITH replacement, each picking
## from `pool` by weight. A repeat-drawn node gains one stake level, so its
## stake always equals its addon count and never breaks the addon cap.
##
## Unicity: addons declaring `unique = true` on their root [SkillNodeAddon]
## scene cannot stack — once one mints on a node, the entry is filtered out
## of later picks for that same node.
##
## `weight_profiles` shares the [WeightProfile] vocabulary with the modifier
## pass, but the addon pass builds no [WeightContext] and does not apply them
## today; nothing from the modifier pass reaches an addon pick.

## Addon density: how many addons the post-loop pass places per 100 generated
## nodes, so maps of every size scale alike. Each one draws a node uniformly
## WITH replacement; a node drawn again gains one stake level. Tentative.
@export_range(0, 200, 0.5) var addons_per_100_nodes: float = 30.0

## Procgen's own per-node addon limit — a draw landing on a full node is
## redrawn. Not the player's stake ceiling: a rare 4th draw stakes the node to
## 4. Tentative.
@export_range(1, 8) var max_addons_per_node: int = 4

@export var pool: AddonPool
@export var weight_profiles: Array[Resource] = []

