@tool
class_name SpellGrantPool
extends Resource

## Pool of spells procgen can roll a [SpellGrant] from. Parallels [AddonPool]
## but deliberately simpler for v1 (#206) — flat per-entry weight, no cost
## budget, no profiles. See [GraphProcgenSpellGrants].

@export var entries: Array[SpellGrantPoolEntry] = []
