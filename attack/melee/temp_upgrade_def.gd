class_name TempUpgradeDef
extends Resource

## One offerable temp-upgrade kind (#406): a REAL [SkillNodeAddon] the melee
## plan `add_child`s onto a blade member for one swing, spent from the same
## blade_size budget as blade members. Authored as a `.tres` under
## `attack/melee/defs/`, listed in [TempUpgradeCatalog]; adding a kind is a new
## def dragged into the catalog, zero code.
##
## Identity contract: consumers compare defs by reference (`kinds.has(def)`,
## `addon.temp_upgrade_def == def`). That holds because a `.tres` loads once
## per process — never `duplicate()` one.

## The wire identity — what a melee plan's wire form carries; `scene` is a
## process-local reference and the catalog's position is not a contract.
@export var id: StringName = &""
## The [SkillNodeAddon] scene to instance when the upgrade is applied. Its
## `resource_path` is the addon's kind ([method SkillNodeAddon.get_kind]), so
## [method SkillNode.can_attach_addon] can ask before an instance exists.
@export var scene: PackedScene
## Spend against [method MeleeAttackPlan.max_blades]' budget.
@export var cost: int = 1
## The entity stat capping how many of this kind one swing may carry (the
## concept's `<concept>_aspect`, floored). Empty = uncapped. Mirrors
## [member AmmoType.per_reload_stat_id]: the def names the aspect it reads.
@export var aspect_stat_id: StringName = &""
