class_name TempUpgradeDef
extends Resource

## One offerable temp-upgrade kind (#406): a REAL [SkillNodeAddon] the melee
## plan `add_child`s onto a blade member for one swing. Its price is authored
## on the scene ([method SkillNodeAddon.get_temp_costs]), never here. Authored as a `.tres` under
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
