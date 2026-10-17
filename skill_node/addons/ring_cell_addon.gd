@tool
class_name RingCellAddon
extends SkillNodeAddon
## Marks a SkillNode in an inner-ring scene as a buyable cell. The grant is the
## base's `entity_modifiers` (a keystone cell grants its scene's root modifiers
## instead). Read once by [RingTable.sample]; never live on the board.

## The [Aspect] this cell feeds; null on a keystone. Display reads its
## `identity`. Typed `Resource` because `aspects/` sits above `skill_node/`
## in the module order (`docs/architecture.md`); cast it where read.
@export var aspect: Resource = null
## The sector's school (an attribute identity, `identity/defs/<attr>.tres`).
@export var sector: Identity = null
## 1, 2, or 0 for a keystone.
@export_range(0, 3) var tier: int = 1
## Ring points per buy. Tentative, easy to change.
@export_range(0, 5) var cost: int = 1
