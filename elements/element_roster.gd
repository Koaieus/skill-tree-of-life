@tool
class_name ElementRoster
extends Resource

## Every authored [Element], as hard `ExtResource` edges
## (`elements/element_roster.tres`) — the [AspectRoster] pattern: runtime code
## reads [method shared] and never scans. `test_element_roster.gd` fails the
## moment `elements/defs/` and this array disagree.

const PATH := "res://elements/element_roster.tres"

@export var elements: Array[Element] = []


static func shared() -> ElementRoster:
	return load(PATH) as ElementRoster


func by_id(id: StringName) -> Element:
	for element in elements:
		if element != null and element.id() == id:
			return element
	return null


## The Element whose count stat is [param stat_id] (`&"fire_element"`), or null.
func for_stat(stat_id: StringName) -> Element:
	for element in elements:
		if element != null and element.stat != null and element.stat.id == stat_id:
			return element
	return null


## The Element [param def] is a member of — its terrain stack or one of its
## movers — or null. The one way to ask "is this status a member, and of what".
func for_status(def: StatusDef) -> Element:
	if def == null:
		return null
	for element in elements:
		if element != null and (element.terrain == def or element.movers.has(def)):
			return element
	return null
