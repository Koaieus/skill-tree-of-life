@tool
class_name AmmoTypeRoster
extends Resource

## Every authored [AmmoType], as hard `ExtResource` edges — the one place the
## fixed volley order is read (`attack/ammo/ammo_type_roster.tres`). The
## [StatDefRoster] pattern: a directory scan of `attack/ammo/types/` does not
## survive export, so runtime code preloads this resource and never scans.
##
## [method sorted] hands the types back in ascending [member AmmoType.order]
## (armour-breaking first … base last); [method base_type] is the one whose
## bin the node-local `arrows_per_reload` mints, every other type is a flat
## entity-board special (see [method Entity.reload]).

## The base arrow's id — the bin `arrows_per_reload` fills.
const BASE_ID: StringName = &"arrow"

@export var types: Array[AmmoType] = []


func sorted() -> Array[AmmoType]:
	var out: Array[AmmoType] = types.duplicate()
	out.sort_custom(func(a: AmmoType, b: AmmoType) -> bool: return a.order < b.order)
	return out


func by_id(id: StringName) -> AmmoType:
	for t in types:
		if t.id == id:
			return t
	return null


func base_type() -> AmmoType:
	return by_id(BASE_ID)
