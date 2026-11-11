extends GutTest

## #1796 — the terrain readout rows. Drives a REAL unowned [SkillNode] through
## [method NodeCombat.add_terrain] and the panel's public [method
## EffectReadoutPanel.bind], then reads the rows back off [SlabRow]s. Every
## expected count is computed from T / the cap and every expected verb from the
## band's own [member ElementBand.travel] — never a literal band name, count or
## travel word.
##
## Fire's bands are shared roster resources, so [method before_each] snapshots
## every band's travel and go_off and [method after_each] restores ALL of them
## unconditionally.

const _PANEL_SCENE := preload("res://ui/tooltip_fan/panels/effect_readout_panel.tscn")

var _w: TestWorld
var _hub: SkillNode
var _leaf: SkillNode
var _fire: Element
var _band_travel: Array = []
var _band_go_off: Array = []


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	_hub = _w.add_node(&"Hub")
	_leaf = _w.add_node(&"Leaf")
	_w.link(_hub, _leaf)
	await get_tree().process_frame
	_fire = ElementRoster.shared().by_id(&"fire")
	_band_travel.clear()
	_band_go_off.clear()
	for band in _fire.bands:
		_band_travel.append(band.travel)
		_band_go_off.append(band.go_off)


func after_each() -> void:
	for i in _fire.bands.size():
		_fire.bands[i].travel = _band_travel[i]
		_fire.bands[i].go_off = _band_go_off[i]
	CombatWorld.reset_live()


func _primed(e: Element) -> ElementBand:
	return e.bands[0]


func _overflow(e: Element) -> ElementBand:
	return e.bands[e.bands.size() - 1]


func _panel() -> EffectReadoutPanel:
	var panel := _PANEL_SCENE.instantiate() as EffectReadoutPanel
	add_child_autofree(panel)
	return panel


func _row_texts(panel: EffectReadoutPanel) -> Array[String]:
	var out: Array[String] = []
	for row in panel._rows.get_children():
		out.append((row as SlabRow)._label.text)
	return out


## The travel word for [param travel], mirroring the panel's own map — the test
## asks the band, never pinning "spreads" itself.
func _travel_word(travel: ElementBand.Travel) -> String:
	match travel:
		ElementBand.Travel.ENDS:
			return "ends here"
		ElementBand.Travel.CONDUCTS:
			return "conducts"
		ElementBand.Travel.SPREADS:
			return "spreads"
	return ""


func test_unowned_node_past_threshold_shows_excess_and_the_bands_travel() -> void:
	assert_null(_leaf.owned_by, "precondition: the fixture node is unowned")
	var combat := _leaf.get_combat()
	var t := combat.terrain_threshold()
	var count := t + 1
	combat.add_terrain(_fire, count)
	var band := combat.terrain_band(_fire)
	assert_eq(band, _primed(_fire), "precondition: past T sits in the primed band")
	var panel := _panel()
	panel.bind(_leaf, _w.graph)
	assert_true(panel.has_content(), "terrain alone is content on an unowned node")
	var joined := "\n".join(_row_texts(panel))
	assert_string_contains(joined, TerrainBars.label_for(_leaf, _fire))
	assert_string_contains(joined, "excess %d" % (count - t))
	assert_string_contains(joined, _travel_word(band.travel))


func test_go_off_row_appears_only_when_the_band_has_one() -> void:
	var combat := _leaf.get_combat()
	combat.add_terrain(_fire, combat.terrain_threshold() + 1)
	var band := combat.terrain_band(_fire)
	band.go_off = null
	var panel := _panel()
	panel.bind(_leaf, _w.graph)
	assert_false("\n".join(_row_texts(panel)).contains("Goes off"),
		"a null go-off must never render a 0% row")
	band.go_off = GoOff.new()
	panel.bind(_leaf, _w.graph)
	var joined := "\n".join(_row_texts(panel))
	assert_string_contains(joined, "Goes off")
	assert_string_contains(joined, "Goes off: %d%% of the hit" % int(band.go_off.share * 100.0))


func test_past_the_cap_the_overflow_band_answers_with_its_own_travel_and_go_off() -> void:
	var combat := _leaf.get_combat()
	var primed := _primed(_fire)
	var overflow := _overflow(_fire)
	assert_true(overflow.at_cap, "precondition: the last band sits at the cap")
	var other := ElementBand.Travel.ENDS
	if primed.travel == other:
		other = ElementBand.Travel.CONDUCTS
	overflow.travel = other
	assert_ne(overflow.travel, primed.travel, "precondition: a different verb from the primed band")
	overflow.go_off = GoOff.new()
	combat.add_terrain(_fire, combat.terrain_cap() + 1)
	assert_eq(combat.terrain_band(_fire), overflow,
		"precondition: past the cap sits in the overflow band")
	var panel := _panel()
	panel.bind(_leaf, _w.graph)
	var joined := "\n".join(_row_texts(panel))
	assert_string_contains(joined, _travel_word(overflow.travel))
	assert_false(joined.contains(_travel_word(primed.travel)),
		"the overflow band answers with its own travel, never the primed band's")
	assert_string_contains(joined, "Goes off: %d%% of the hit" % int(overflow.go_off.share * 100.0))


func test_no_terrain_has_no_terrain_rows_and_no_content() -> void:
	var panel := _panel()
	panel.bind(_leaf, _w.graph)
	assert_false(panel.has_content(), "a bare node has nothing to read out")
	assert_eq(_row_texts(panel).size(), 0)
