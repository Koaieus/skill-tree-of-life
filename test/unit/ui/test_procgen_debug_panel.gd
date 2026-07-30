extends GutTest

## Tooltip V2 (#292) — the procgen debug panel: substance parity with the V1
## `skill_node_tooltip.gd::_populate_procgen_debug` block #235 deleted, absence
## when the meta is absent, and the removability #292 makes an explicit
## acceptance criterion rather than a design aspiration.

const _FAN := preload("res://ui/tooltip_fan/fan.tscn")
const _PANEL := preload("res://ui/tooltip_fan/panels/procgen_debug_panel.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")

## A phase-2 footprint with the slot split — the richest shape
## `graph_procgen.gd` stamps, and the one V1 rendered in full.
const _FULL_FOOTPRINT := {
	"phase": "primary",
	"budget": 12,
	"slots": 3,
	"primary_slots": 2,
	"off_slots": 1,
	"peak_primary_cost": 7,
	"off_cap": 4,
	"role_tags": ["bruiser", "anchor"],
}

## Files under `ui/` allowed to mention `procgen_footprint` — just this panel.
##
## Held a temporary allowance for `skill_node_tooltip.gd` between #292 and #235;
## that file is now deleted, so the list is back to being the real answer.
const _META_READERS_ALLOWED: Array[String] = [
	"res://ui/tooltip_fan/panels/procgen_debug_panel.gd",
]

var _panel: ProcgenDebugPanel
var _node: SkillNode


func before_each() -> void:
	_panel = _PANEL.instantiate() as ProcgenDebugPanel
	add_child(_panel)
	autofree(_panel)
	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child(_node)
	autofree(_node)


func _rows_text() -> Array[String]:
	var out: Array[String] = []
	for child in (_panel.get_node("%Rows") as VBoxContainer).get_children():
		if child is Label:
			out.append((child as Label).text)
	return out


func _joined() -> String:
	return "\n".join(_rows_text())


# --- absence ------------------------------------------------------------------

func test_a_node_without_the_meta_has_no_content() -> void:
	_panel.bind(_node, null)
	assert_false(_panel.has_content(),
		"a hand-authored node carries no procgen_footprint, so the unit must be suppressed")
	assert_eq(_rows_text().size(), 0, "and it must render no rows — no empty box")


func test_an_unbound_panel_has_no_content() -> void:
	assert_false(_panel.has_content(), "never bound, nothing to show")


# --- presence + substance parity with V1 --------------------------------------

func test_a_node_with_a_footprint_has_content() -> void:
	_node.set_meta("procgen_footprint", _FULL_FOOTPRINT)
	_panel.bind(_node, null)
	assert_true(_panel.has_content())


## The meta is stamped by `graph_procgen.gd:187` with a plain String key while
## this panel reads it with a StringName. Godot treats those as the same meta
## key — asserted rather than assumed, because a mismatch would silently render
## nothing at all.
func test_the_string_stamped_meta_is_found_by_the_stringname_read() -> void:
	_node.set_meta("procgen_footprint", _FULL_FOOTPRINT)
	_panel.bind(_node, null)
	assert_true(_panel.has_content(),
		"set_meta(String) must be readable as has_meta(StringName)")


func test_it_renders_the_procgen_tag() -> void:
	_node.set_meta("procgen_footprint", _FULL_FOOTPRINT)
	_panel.bind(_node, null)
	assert_eq(_rows_text()[0], "[procgen]", "the tag leads, as it did in V1")


func test_it_renders_the_budget_and_slot_split() -> void:
	_node.set_meta("procgen_footprint", _FULL_FOOTPRINT)
	_panel.bind(_node, null)
	assert_string_contains(_joined(), "budget 12 · slots 3 (2P+1O)")


func test_it_renders_the_peak_and_off_cap_pair() -> void:
	_node.set_meta("procgen_footprint", _FULL_FOOTPRINT)
	_panel.bind(_node, null)
	assert_string_contains(_joined(), "peak 7 · off_cap 4")


func test_it_renders_the_role_tags() -> void:
	_node.set_meta("procgen_footprint", _FULL_FOOTPRINT)
	_panel.bind(_node, null)
	assert_string_contains(_joined(), "role: bruiser, anchor")


func test_a_footprint_without_slots_falls_back_to_budget_and_phase() -> void:
	# V1's `elif budget >= 0` branch — the shape earlier procgen phases stamp.
	_node.set_meta("procgen_footprint", {"phase": "seed", "budget": 4})
	_panel.bind(_node, null)
	assert_string_contains(_joined(), "budget 4 · phase seed")


func test_role_tags_are_omitted_when_empty() -> void:
	_node.set_meta("procgen_footprint", {"phase": "seed", "budget": 4, "role_tags": []})
	_panel.bind(_node, null)
	assert_false(_joined().contains("role:"), "no tags means no role line, not an empty one")


func test_rebinding_a_metaless_node_clears_the_previous_footprint() -> void:
	_node.set_meta("procgen_footprint", _FULL_FOOTPRINT)
	_panel.bind(_node, null)
	assert_gt(_rows_text().size(), 1, "precondition: rows rendered")
	var bare := _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child(bare)
	autofree(bare)
	_panel.bind(bare, null)
	assert_eq(_rows_text().size(), 0, "a live re-bind (#314) must clear stale rows")


# --- #292: it must stay cleanly removable -------------------------------------

func test_deleting_the_unit_from_the_fan_leaves_the_fan_working() -> void:
	# #292 decision 4, asserted rather than asserted-to-be-true-later: pull the
	# unit out and the fan must still derive its geometry for everyone else.
	var fan := _FAN.instantiate()
	add_child(fan)
	autofree(fan)
	await get_tree().process_frame
	var unit := fan.find_child("ProcgenDebug", true, false)
	assert_not_null(unit, "precondition: the fan mounts the debug unit")
	var before: int = (fan as FanAnchorDriver).units_in_fan_order().size()

	unit.get_parent().remove_child(unit)
	unit.free()
	(fan as FanAnchorDriver).refresh()
	await get_tree().process_frame

	var ordered := (fan as FanAnchorDriver).units_in_fan_order()
	assert_eq(ordered.size(), before - 1, "exactly one unit should be gone")
	for u in ordered:
		var trace: FanTrace = u.get_node_or_null("%Trace")
		assert_not_null(trace, "%s must still have its trace" % u.name)
		assert_false(is_nan(trace.to_point.x), "%s's terminus must still derive" % u.name)


func test_nothing_else_in_the_ui_reads_the_procgen_footprint_meta() -> void:
	# #292 acceptance: this panel is the meta's only UI consumer, so deleting it
	# takes the whole dependency with it. Source-inspected so it stays true after
	# the next edit rather than only today.
	var offenders: Array[String] = []
	for path in _gd_files_under("res://ui"):
		if path in _META_READERS_ALLOWED:
			continue
		var src := FileAccess.get_file_as_string(path)
		if src.contains("procgen_footprint"):
			offenders.append(path)
	assert_eq(offenders, [] as Array[String],
		"only procgen_debug_panel.gd may read procgen_footprint under ui/")


func _gd_files_under(root: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var path := root.path_join(entry)
		if dir.current_is_dir():
			out.append_array(_gd_files_under(path))
		elif entry.ends_with(".gd"):
			out.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return out
