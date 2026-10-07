@tool
class_name StatusRoster
extends Resource

## Every authored [StatusDef] (`effects/status/*.tres`), as hard `ExtResource`
## edges (`effects/status_roster.tres`) — the [StatDefRoster] pattern: a
## directory scan does not survive export, so runtime code reads [method shared]
## and never scans. `test_status_roster.gd` fails the moment the directory and
## this array disagree.
##
## The concept id → status door for code below `aspects` (an infused concept a
## spell does not list resolves its rider here); `AspectRoster` ranks above
## `attack`, this sits under it.

const PATH := "res://effects/status_roster.tres"

@export var statuses: Array[StatusDef] = []


static func shared() -> StatusRoster:
	return load(PATH) as StatusRoster


## The status of concept [param concept_id] — keyed on
## [member StatusDef.identity], falling back to its own id; null if none.
func by_concept(concept_id: StringName) -> StatusDef:
	for status in statuses:
		if status == null:
			continue
		var id := status.identity.id if status.identity != null and not status.identity.id.is_empty() \
				else status.id
		if id == concept_id:
			return status
	return null
