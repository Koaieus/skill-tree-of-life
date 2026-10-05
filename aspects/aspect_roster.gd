@tool
class_name AspectRoster
extends Resource

## Every authored [Aspect], as hard `ExtResource` edges
## (`aspects/aspect_roster.tres`). The [StatDefRoster] pattern: a directory
## scan of `aspects/defs/` does not survive export, so runtime code reads
## [method shared] and never scans. `test_aspect_roster.gd` fails the moment
## the directory and this array disagree.

const PATH := "res://aspects/aspect_roster.tres"

@export var aspects: Array[Aspect] = []


static func shared() -> AspectRoster:
	return load(PATH) as AspectRoster


func by_id(id: StringName) -> Aspect:
	for aspect in aspects:
		if aspect.id() == id:
			return aspect
	return null


## The Aspect whose count stat is [param stat_id] (`&"poison_aspect"`), or null.
func for_stat(stat_id: StringName) -> Aspect:
	for aspect in aspects:
		if aspect.stat != null and aspect.stat.id == stat_id:
			return aspect
	return null
