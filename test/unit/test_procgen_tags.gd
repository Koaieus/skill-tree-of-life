extends GutTest

## Tag-registry typo backstop. Catches anything the `@tool` configuration
## warnings missed: a profile or pool entry whose `tags` reference a
## StringName that isn't declared in `procgen/tags.tres`.
##
## This is the belt-and-braces layer per docs/domain/procgen-v2.md
## ("Identifiers & validation"). For each procgen .tres on disk, load it,
## walk its tag-bearing fields, and assert every member is in the canonical
## set.

const _PROCGEN_DIR := "res://procgen"
const _TAG_FIELDS := [
	&"tags",  # ModifierPoolEntry, AddonPoolEntry
]


var _registry: TagRegistry


func before_all() -> void:
	_registry = TagRegistry.canonical()


func test_canonical_registry_loads() -> void:
	assert_not_null(_registry, "res://procgen/archetypes/tags.tres should load as TagRegistry")
	assert_gt(_registry.tags.size(), 0, "registry should declare at least one tag")


func test_parallel_arrays_match_length() -> void:
	assert_eq(
		_registry.tags.size(), _registry.descriptions.size(),
		"tags and descriptions must be parallel — author one description per tag"
	)


func test_no_duplicate_tags() -> void:
	var seen := {}
	for t in _registry.tags:
		assert_false(t in seen, "duplicate tag in registry: %s" % String(t))
		seen[t] = true


func test_has_tag_lookup() -> void:
	assert_true(_registry.has_tag(&"str"), "str should be a canonical tag")
	assert_false(_registry.has_tag(&"strr"), "strr should NOT be a canonical tag (typo)")


func test_unknown_tags_filter() -> void:
	var bad: Array = [&"str", &"definitely_not_a_tag", &"int"]
	var unknown := _registry.unknown_tags(bad)
	assert_eq(unknown.size(), 1)
	assert_eq(unknown[0], &"definitely_not_a_tag")


func test_all_procgen_tres_use_declared_tags() -> void:
	# Walks every .tres under procgen/, inspects fields that conventionally
	# carry tags, and asserts each tag is declared in the canonical registry.
	# Quiet today (no tres carries `tags` yet); becomes load-bearing once
	# step 2 lands `ModifierPoolEntry.tags`.
	var offenders: Array = []
	for path in _list_tres_recursive(_PROCGEN_DIR):
		var res: Resource = load(path)
		if res == null:
			continue
		_collect_offenders(res, path, offenders)
	assert_eq(
		offenders.size(), 0,
		"undeclared tags found: %s" % str(offenders)
	)


func _list_tres_recursive(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path + "/" + name
		if dir.current_is_dir() and not name.begins_with("."):
			out.append_array(_list_tres_recursive(full))
		elif name.ends_with(".tres"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out


func _collect_offenders(res: Resource, path: String, offenders: Array) -> void:
	for field in _TAG_FIELDS:
		var v: Variant = res.get(field)
		if v == null:
			continue
		if v is Array or v is PackedStringArray:
			var unknown := _registry.unknown_tags(v)
			for tag in unknown:
				offenders.append("%s :: %s :: %s" % [path, field, String(tag)])
