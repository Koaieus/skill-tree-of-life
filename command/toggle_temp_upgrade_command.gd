class_name ToggleTempUpgradeCommand
extends NodeCommand

## "Put this temp upgrade on that node — or take it off again if it is already
## there." A TOGGLE, not an apply: `MeleeAttackPlan.toggle_temp_upgrade`
## refunds an identical upgrade already on the node (#406).
##
## Named for the toggle per the owner's correction on #509, which also fixed
## the payload: `(entity_id, node_id)` is not enough to express the action.
## `PlayerInputController.apply_armed_temp_upgrade_to(skill_node)` takes only
## the node because *which* upgrade comes from PIC-local armed state
## (`_temp_upgrade_arm`), and a host receiving the command cannot know what the
## sender had armed. Hence [member upgrade_id] — the stable wire name of a
## [constant MeleeAttackPlan.TEMP_UPGRADE_CATALOG] entry, resolved back with
## [method MeleeAttackPlan.upgrade_by_id].
##
## This is PLAN state, not board state: it only means anything while a
## [MeleeAttackPlan] is armed. #510 owns moving the method to [BattleSystem]
## and wiring this up; the type is only defined here.

const TAG: StringName = &"toggle_temp_upgrade"

## Which catalog entry, by [code]id[/code].
var upgrade_id: StringName = &""


func _init(entity_id_: int = 0, node_id_: int = 0, upgrade_id_: StringName = &"") -> void:
	super(entity_id_, node_id_)
	upgrade_id = upgrade_id_


func type_tag() -> StringName:
	return TAG


func to_dict() -> Dictionary:
	var d := super()
	d["upgrade_id"] = upgrade_id
	return d


static func from_dict(d: Dictionary) -> ToggleTempUpgradeCommand:
	return ToggleTempUpgradeCommand.new(
		int(d.get("entity_id", 0)),
		int(d.get("node_id", 0)),
		StringName(d.get("upgrade_id", &"")),
	)
