@tool
class_name TagRegistry
extends Resource

## Single source of truth for the StringName tags used by the procgen v2 content
## composition system — pool entries, weight profiles, role decorations.
##
## Authored as `res://procgen/tags.tres`. Designers add a tag by editing that
## file; everything else (`@tool` validators on `ModifierPoolEntry` /
## `WeightProfile`, the GUT typo backstop) reads from it.
##
## `tags` and `descriptions` are parallel arrays — index N of `descriptions`
## documents `tags[N]`. Descriptions are designer-facing; the system only
## reads `tags`.

const CANONICAL_PATH: String = "res://procgen/tags.tres"

@export var tags: Array[StringName] = []
@export var descriptions: PackedStringArray = []


## Lazy-loaded shared instance of `tags.tres`. Returns null if the file is
## absent (the test suite catches that as a hard error; runtime callers fall
## back to permissive behavior).
static var _canonical: TagRegistry = null


static func canonical() -> TagRegistry:
	if _canonical == null and ResourceLoader.exists(CANONICAL_PATH):
		_canonical = load(CANONICAL_PATH) as TagRegistry
	return _canonical


func has_tag(tag: StringName) -> bool:
	return tag in tags


## Returns the subset of `to_check` not present in this registry. Empty array
## means clean. Used by `@tool` config-warning hooks and the GUT backstop.
func unknown_tags(to_check: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for t in to_check:
		var sn := StringName(t)
		if sn == &"":
			continue
		if not has_tag(sn):
			out.append(sn)
	return out


func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	if tags.size() != descriptions.size():
		out.append("tags (%d) and descriptions (%d) must be parallel — same length." % [tags.size(), descriptions.size()])
	var seen := {}
	for t in tags:
		if t in seen:
			out.append("Duplicate tag: %s" % String(t))
		seen[t] = true
	return out
