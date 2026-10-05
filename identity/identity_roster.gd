@tool
class_name IdentityRoster
extends Resource

## Every authored [Identity], as hard `ExtResource` edges
## (`identity/identity_roster.tres`). The [StatDefRoster] pattern: a directory
## scan of `identity/defs/` does not survive export, so runtime code reads
## [method shared] and never scans.

const PATH := "res://identity/identity_roster.tres"

@export var identities: Array[Identity] = []


static func shared() -> IdentityRoster:
	return load(PATH) as IdentityRoster


func by_id(id: StringName) -> Identity:
	for identity in identities:
		if identity.id == id:
			return identity
	return null
