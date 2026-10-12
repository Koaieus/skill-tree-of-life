extends GutTest

## ADR 0059: a primary is a school's root, so no stat link may run primary -> primary.
## The primary set is read from the defs (the children of `attributes`), never named here.

const _BOARDS: Array[String] = [
	"res://entity/default_entity_board.tres",
	"res://entity/blocker/blocker_small_board.tres",
	"res://entity/blocker/blocker_medium_board.tres",
	"res://entity/blocker/blocker_large_board.tres",
	"res://skill_node/default_node_board.tres",
]


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


func test_shipped_boards_have_no_primary_to_primary_link() -> void:
	var primaries := _primary_ids()
	for path in _BOARDS:
		var board: StatBoard = load(path)
		assert_not_null(board, path)
		if board == null:
			continue
		assert_eq(_violations(board.intrinsic_modifiers, primaries), [], path)


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
