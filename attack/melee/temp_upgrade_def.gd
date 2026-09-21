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

## The wire identity — what [ToggleTempUpgradeCommand] carries; `scene` and
## `addon_script` are process-local references and the catalog's position is
## not a contract.
@export var id: StringName = &""
## The [SkillNodeAddon] scene to instance when the upgrade is applied.
@export var scene: PackedScene
## The addon's script — [method SkillNode.can_attach_addon]'s uniqueness check
## needs the Script identity before an instance exists.
@export var addon_script: Script
## Spend against [method MeleeAttackPlan.max_blades]' budget.
@export var cost: int = 1
