@tool
class_name AddonPool
extends Resource

## Universal addon pool — parallels [ModifierPool] but draws [AddonPoolEntry]
## and mints scene instances. Roll loop mirrors the modifier pass: pick a
## weighted-and-affordable entry, mint, subtract its cost from the addon
## budget, repeat. Profiles compose multiplicatively against
## [member AddonPoolEntry.weight].

@export var entries: Array[AddonPoolEntry] = []
