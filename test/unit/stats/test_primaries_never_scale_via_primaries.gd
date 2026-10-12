extends GutTest

## ADR 0059: a primary is a school's root, so no stat link may run primary -> primary.
## The primary set is read from the defs (the children of `attributes`), never named here.

const _SKIP_DIRS: Array[String] = [".godot", ".worktrees", "addons"]
## Boards with formula links today (default entity + 3 blockers); discovery must find at least these.
const _KNOWN_FLOOR := 4


## Every `.tres` that mentions a formula source (so can carry a link) and loads as a
## stat board or a core class, found by walking res:// (editor/test code, never runtime).
func _link_carriers(dir: String = "res://") -> Array[Resource]:
	var out: Array[Resource] = []
	for sub in DirAccess.get_directories_at(dir):
		if _SKIP_DIRS.has(sub) or sub.begins_with("."):
			continue
		out.append_array(_link_carriers(dir.path_join(sub)))
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".tres"):
			continue
		var path := dir.path_join(file)
		if not FileAccess.get_file_as_string(path).contains("source_stat_id"):
			continue
		var res := load(path)
		if res is StatBoard or res is CoreClass:
			out.append(res)
	return out


func _links_of(res: Resource) -> Array:
	return res.intrinsic_modifiers if res is StatBoard else res.modifiers


func _primary_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for def in StatRegistry.get_all_defs():
		if def.parent_ids.has(&"attributes"):
			out.append(def.id)
	return out


## Every "<source> -> <target>" where both ends are primaries. A link is a modifier
## whose formula reads a primary and whose target stat is another primary.
func _violations(mods: Array, primaries: Array[StringName]) -> Array[String]:
	var out: Array[String] = []
	for m in mods:
		if m == null or m.formula == null or not primaries.has(m.stat_id):
			continue
		for input in m.formula.get_input_ids():
			var src := StatFormula.base_of(input)
			if primaries.has(src):
				out.append("%s -> %s" % [src, m.stat_id])
	return out


func test_primary_set_is_discovered_from_defs() -> void:
	var primaries := _primary_ids()
	assert_gt(primaries.size(), 1, "attributes has primary children")
	assert_false(primaries.has(&"attributes"))


func test_scratch_primary_to_primary_link_is_caught() -> void:
	var primaries := _primary_ids()
	var link := StatModifier.new()
	link.stat_id = primaries[0]
	var f := LinearFormula.new()
	f.source_stat_id = primaries[1]
	link.formula = f
	assert_eq(_violations([link], primaries).size(), 1, "the scratch link is flagged")


func test_primary_to_non_primary_link_is_allowed() -> void:
	var primaries := _primary_ids()
	var link := StatModifier.new()
	link.stat_id = &"vision_range"
	var f := LinearFormula.new()
	f.source_stat_id = primaries[0]
	link.formula = f
	assert_eq(_violations([link], primaries).size(), 0)


func test_shipped_boards_and_core_classes_have_no_primary_to_primary_link() -> void:
	var primaries := _primary_ids()
	var carriers := _link_carriers()
	var boards := 0
	for res in carriers:
		if res is StatBoard:
			boards += 1
		assert_eq(_violations(_links_of(res), primaries), [], res.resource_path)
	assert_gte(boards, _KNOWN_FLOOR, "discovery found the boards known to carry links")


## Positive control: the scan really reads formulas off the board (a uid mismatch would null them).
func test_default_board_scan_sees_primary_sourced_formulas() -> void:
	var primaries := _primary_ids()
	var board: StatBoard = load("res://entity/default_entity_board.tres")
	var seen := 0
	for m in board.intrinsic_modifiers:
		if m == null or m.formula == null:
			continue
		for input in m.formula.get_input_ids():
			if primaries.has(StatFormula.base_of(input)):
				seen += 1
	assert_gt(seen, 0, "default board has primary -> non-primary links")
