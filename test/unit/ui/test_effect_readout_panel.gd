extends GutTest

## #621 — the aura|effect readout panel. Drives a real [Graph] +
## [SkillNode] + [Entity] fixture through the real [EffectContext] grant path
## (`inst.context.grant(mod, node)`) rather than mocking [NodeEffectReadout],
## so the read side ([method NodeEffectReadout.gather], which walks
## [method Entity.get_effects] and [method EffectInstance.handles_for]) is
## exercised for real. The effect itself is a bare [StatEffect] with no
## `modifiers` (so `_on_granted` is a no-op) — the test grants directly
## through the context it's handed, which is the same seam [AuraEffect] uses.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PANEL_SCENE := preload("res://ui/tooltip_fan/panels/effect_readout_panel.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

var _graph: Graph
var _node: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_node = _SKILL_NODE_SCENE.instantiate()
	_graph.add_skill_node(_node)


func _spawn_entity(faction: Faction = null) -> Entity:
	var ent := Entity.new()
	ent.display_name = "E"
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	if faction != null:
		ent.faction = faction
	# Real production wiring (#621's read path scans exactly this container) —
	# see GameRoot.spawn_entity / Graph._ready's entity_id minting.
	_graph.entities_container.add_child(ent)
	autofree(ent)
	return ent


func _mod(stat_id: StringName, op: StatModifier.Operation, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = op
	m.value = value
	return m


## Grants [param mod] to [member _node] through a fresh no-op [StatEffect],
## named [param effect_name] — the minimal real seam an [AuraEffect] also
## grants through ([method EffectContext.grant]/`grant_scaled`).
func _grant(entity: Entity, effect_name: String, mod: StatModifier) -> void:
	var effect := StatEffect.new()
	effect.display_name = effect_name
	var inst := entity.grant_effect(effect)
	inst.context.grant(mod, _node)


func _panel() -> EffectReadoutPanel:
	var panel := _PANEL_SCENE.instantiate() as EffectReadoutPanel
	add_child_autofree(panel)
	return panel


func _row_texts(panel: EffectReadoutPanel) -> Array[String]:
	var out: Array[String] = []
	for row in panel._rows.get_children():
		out.append((row as SlabRow)._label.text)
	return out


# --- acceptance 1: a row per affecting effect, name + scaled value ----------

func test_row_shows_effect_name_and_value() -> void:
	var ent := _spawn_entity()
	_grant(ent, "Coil (hops)", _mod(&"armor", StatModifier.Operation.ADD_BASE, 3.0))
	var panel := _panel()
	panel.bind(_node, _graph)
	assert_true(panel.has_content())
	var texts := _row_texts(panel)
	assert_eq(texts.size(), 1)
	assert_string_contains(texts[0], "Coil (hops)")
	assert_string_contains(texts[0], "+3 Armor")


# --- acceptance 2/3: neutral element hides ----------------------------------

func test_add_base_neutral_element_hides() -> void:
	var ent := _spawn_entity()
	_grant(ent, "Coil (hops)", _mod(&"armor", StatModifier.Operation.ADD_BASE, 0.0))
	var panel := _panel()
	panel.bind(_node, _graph)
	assert_false(panel.has_content(), "+0 ADD_BASE must hide")


func test_multiply_neutral_element_hides() -> void:
	var ent := _spawn_entity()
	_grant(ent, "Coil (hops)", _mod(&"armor", StatModifier.Operation.MULTIPLY, 1.0))
	var panel := _panel()
	panel.bind(_node, _graph)
	assert_false(panel.has_content(), "×1 MULTIPLY must hide")


# --- acceptance 3 (explicit): ×0 MULTIPLY is annihilation, never hides -----

func test_multiply_by_zero_is_shown_not_hidden() -> void:
	var ent := _spawn_entity()
	_grant(ent, "Coil (space)", _mod(&"armor", StatModifier.Operation.MULTIPLY, 0.0))
	var panel := _panel()
	panel.bind(_node, _graph)
	assert_true(panel.has_content(), "×0 must never hide — it's annihilation, not neutral")
	assert_string_contains(_row_texts(panel)[0], "×0")


# --- acceptance 4: SET never hides, regardless of value ---------------------

func test_set_is_always_shown() -> void:
	var ent := _spawn_entity()
	_grant(ent, "Coil (space)", _mod(&"armor", StatModifier.Operation.SET, 0.0))
	var panel := _panel()
	panel.bind(_node, _graph)
	assert_true(panel.has_content(), "SET has no neutral element — it never hides")


# --- acceptance 5: two sources, shown separately with opposite signs -------

func test_two_sources_shown_as_separate_rows_with_opposite_signs() -> void:
	var ent := _spawn_entity()
	_grant(ent, "Coil (hops)", _mod(&"armor", StatModifier.Operation.ADD_BASE, 4.0))
	_grant(ent, "Coil (space)", _mod(&"armor", StatModifier.Operation.ADD_BASE, -6.0))
	var panel := _panel()
	panel.bind(_node, _graph)
	var texts := _row_texts(panel)
	assert_eq(texts.size(), 2, "aggregation is per-source, never summed into one row")
	var joined := "\n".join(texts)
	assert_string_contains(joined, "+4 Armor")
	assert_string_contains(joined, "-6 Armor")


# --- acceptance 6: hiding every row leaves no panel -------------------------

func test_hiding_every_row_suppresses_the_whole_panel() -> void:
	var ent := _spawn_entity()
	_grant(ent, "Coil (hops)", _mod(&"armor", StatModifier.Operation.ADD_BASE, 0.0))
	_grant(ent, "Coil (space)", _mod(&"armor", StatModifier.Operation.MULTIPLY, 1.0))
	var panel := _panel()
	panel.bind(_node, _graph)
	assert_false(panel.has_content())
	assert_eq(_row_texts(panel).size(), 0)


func test_no_effects_at_all_has_no_content() -> void:
	var panel := _panel()
	panel.bind(_node, _graph)
	assert_false(panel.has_content())


# --- acceptance 7: ten neutral rows whose aggregate is non-zero roll up ----

func test_many_individually_neutral_rows_roll_up_when_the_aggregate_is_real() -> void:
	var ent := _spawn_entity()
	# INT-typed armor: ten +0.4 ADD_BASE grants each individually display as
	# "+0" (hidden), but their sum (4.0) does not.
	for i in 10:
		_grant(ent, "Falloff %d" % i, _mod(&"armor", StatModifier.Operation.ADD_BASE, 0.4))
	var panel := _panel()
	panel.bind(_node, _graph)
	assert_true(panel.has_content(), "a real +4 aggregate must not vanish silently")
	var texts := _row_texts(panel)
	assert_eq(texts.size(), 1, "the ten hidden rows collapse into one rolled-up row")
	assert_string_contains(texts[0], "10")
	assert_string_contains(texts[0], "+4 Armor")


func test_neutral_in_aggregate_too_truly_hides() -> void:
	var ent := _spawn_entity()
	# Two ADD_BASE rows, +0.3 and -0.3: each individually displays "+0" (INT)
	# and so does their aggregate (0.0) — genuinely hidden, no rollup row.
	_grant(ent, "A", _mod(&"armor", StatModifier.Operation.ADD_BASE, 0.3))
	_grant(ent, "B", _mod(&"armor", StatModifier.Operation.ADD_BASE, -0.3))
	var panel := _panel()
	panel.bind(_node, _graph)
	assert_false(panel.has_content(), "an aggregate that is itself neutral stays hidden")


# --- "does this affect me" (ownership_bit, mechanism only) ------------------

func test_hostile_source_tints_the_row_toward_red() -> void:
	# Distinct factions — [method Entity.attitude_to] reads HOSTILE for two
	# faction-less entities too, but that's a degenerate case this test
	# should not lean on; a real player/NPC split is the honest fixture.
	var mine := _spawn_entity(_PLAYER_FACTION)
	var enemy := _spawn_entity(_NPC_FACTION)
	_node.owned_by = mine
	_grant(mine, "Home Buff", _mod(&"armor", StatModifier.Operation.ADD_BASE, 2.0))
	_grant(enemy, "Enemy Aura", _mod(&"armor", StatModifier.Operation.ADD_BASE, 5.0))
	var panel := _panel()
	panel.bind(_node, _graph)
	var rows: Array = panel._rows.get_children()
	assert_eq(rows.size(), 2)
	# HOSTILE relative to the node's owner shifts the tint toward red — assert
	# the two rows' tints actually differ, without pinning an exact value.
	var t0: Color = (rows[0] as SlabRow)._slab.tint_color
	var t1: Color = (rows[1] as SlabRow)._slab.tint_color
	assert_ne(t0, t1, "a hostile-sourced row must render with a different tint than a friendly one")


# --- acceptance 8: a formula-bearing row shows its EFFECTIVE value ----------

## A stand-in for any [StatFormula] whose `compute` reads the board — the
## acceptance is about which NUMBER the row prints (coefficient vs. effective),
## not about any particular formula's shape, so a fixed multiplier is the
## honest fixture. `per_phrase` is left empty on purpose: the readout must not
## fall back to [method StatModifier.format]'s "per <phrase>" coefficient
## branch, and an empty phrase makes a regression there visible as a bare
## coefficient rather than as a differently-worded sentence.
class FixedFormula extends StatFormula:
	func compute(_board: StatBoard) -> float:
		return 3.0


func test_formula_bearing_row_shows_effective_not_raw_value() -> void:
	var ent := _spawn_entity()
	var mod := _mod(&"armor", StatModifier.Operation.ADD_BASE, 2.0)
	mod.formula = FixedFormula.new()
	_grant(ent, "Coil (hops)", mod)
	var panel := _panel()
	panel.bind(_node, _graph)
	var texts := _row_texts(panel)
	assert_eq(texts.size(), 1)
	assert_string_contains(texts[0], "+6 Armor", "2.0 coefficient × formula 3.0 — the effective value")
	assert_false(texts[0].contains("+2 Armor"), "the raw coefficient must never be what the row prints")


func test_formula_bearing_row_hides_on_its_effective_neutral() -> void:
	var ent := _spawn_entity()
	# Raw .value is a real 2.0 — only the EFFECTIVE value is neutral. Hiding
	# on the raw value would keep this row; hiding on the effective one drops
	# it, which is the rule (`get_effective_value`, never `.value`).
	var mod := _mod(&"armor", StatModifier.Operation.ADD_BASE, 2.0)
	mod.formula = ZeroFormula.new()
	_grant(ent, "Coil (hops)", mod)
	var panel := _panel()
	panel.bind(_node, _graph)
	assert_false(panel.has_content(), "a formula that computes to 0 makes the row neutral, raw .value notwithstanding")


class ZeroFormula extends StatFormula:
	func compute(_board: StatBoard) -> float:
		return 0.0


# --- acceptance 9/10/11: the cap + carousel ---------------------------------

## `count` rows that are all guaranteed to SHOW: SET has no neutral element, so
## none of them is ever a hide candidate and none can be swallowed by the
## rollup. One effect per row keeps them per-source-distinct (#621's "shown per
## source, never summed"), which is what makes them `count` separate rows.
func _grant_many(ent: Entity, count: int) -> void:
	for i in count:
		_grant(ent, "Aura %d" % i, _mod(&"armor", StatModifier.Operation.SET, float(i + 1)))


# paginate() is the whole of the carousel a headless test can catch wrong.

func test_paginate_returns_one_page_when_the_rows_fit() -> void:
	assert_eq(EffectReadoutPanel.paginate([1, 2, 3, 4], 4).size(), 1)
	assert_eq(EffectReadoutPanel.paginate([1], 4).size(), 1)


func test_paginate_returns_nothing_for_no_rows() -> void:
	assert_eq(EffectReadoutPanel.paginate([], 4).size(), 0)


func test_paginate_balances_pages_instead_of_leaving_a_leftover() -> void:
	# 11 rows at a cap of 4: three pages (ceil), spread 4/4/3 — never 4/4/4/... + 1.
	var pages := EffectReadoutPanel.paginate(range(11), 4)
	assert_eq(pages.size(), 3)
	assert_eq([pages[0].size(), pages[1].size(), pages[2].size()], [4, 4, 3])


func test_paginate_never_exceeds_the_cap_and_never_empties_a_page() -> void:
	for n in range(1, 40):
		for cap in [1, 3, 4, 7]:
			var pages := EffectReadoutPanel.paginate(range(n), cap)
			for page in pages:
				assert_between(page.size(), 1, cap,
					"n=%d cap=%d produced a page of %d" % [n, cap, page.size()])


func test_paginate_preserves_every_row_exactly_once_in_order() -> void:
	var flat: Array = []
	for page in EffectReadoutPanel.paginate(range(23), 4):
		flat.append_array(page)
	assert_eq(flat, range(23) as Array,
		"waiting out the carousel must show every row, once, in order")


# acceptance 10: under the cap, nothing changes.

func test_under_the_cap_there_is_no_carousel_and_no_page_indicator() -> void:
	var ent := _spawn_entity()
	_grant_many(ent, 3)
	var panel := _panel()
	panel.bind(_node, _graph)
	assert_false(panel.is_paging(), "three rows under a cap of four must not page")
	assert_eq(_row_texts(panel).size(), 3, "every row is up at once")
	assert_eq(panel._header.subheader, panel._authored_subheader,
		"the authored subheader survives — no page indicator when there is one page")


func test_binding_does_not_clobber_the_authored_header() -> void:
	var panel := _panel()
	panel.bind(_node, _graph)
	assert_eq(panel._header.header, "EFFECTS")
	assert_false(panel._authored_subheader.is_empty(),
		"the scene authors a subheader; the panel must cache it, not overwrite it")


# acceptance 9: over the cap, the panel pages instead of growing.

func test_over_the_cap_the_panel_pages_and_holds_at_the_cap() -> void:
	var ent := _spawn_entity()
	_grant_many(ent, 10)
	var panel := _panel()
	panel.bind(_node, _graph)
	assert_true(panel.is_paging())
	assert_eq(panel._pages.size(), 3, "10 rows at a cap of 4 is three pages")
	assert_eq(_row_texts(panel).size(), 4, "only one page's worth is mounted at a time")
	assert_string_contains(panel._header.subheader, "1 / 3")


func test_the_carousel_cycles_every_page_and_wraps() -> void:
	var ent := _spawn_entity()
	_grant_many(ent, 10)
	var panel := _panel()
	panel.bind(_node, _graph)
	var seen: Array[String] = []
	for i in panel._pages.size():
		seen.append_array(_row_texts(panel))
		panel.advance_page()
	assert_eq(seen.size(), 10, "one full cycle shows all ten rows")
	assert_eq(panel._page_index, 0, "the cycle wraps back to the first page")
	assert_string_contains(panel._header.subheader, "1 / 3")


func test_the_panel_never_grows_past_its_authored_envelope() -> void:
	var ent := _spawn_entity()
	_grant_many(ent, 24)
	var panel := _panel()
	panel.bind(_node, _graph)
	await wait_process_frames(2)
	var skin := panel.get_skin()
	assert_almost_eq(skin.size.y, skin.custom_minimum_size.y, 1.0,
		"24 effects must not grow the panel past the envelope the scene authored")
	# Not a vacuous assert: the same fixture with `max_rows_per_page = 24`
	# measures 817px against the authored 180 — the cap is what holds it.


# acceptance 11: an all-hidden panel is suppressed outright, never cycled.

func test_an_all_hidden_panel_has_no_pages_to_cycle() -> void:
	var ent := _spawn_entity()
	for i in 6:
		_grant(ent, "Falloff %d" % i, _mod(&"armor", StatModifier.Operation.MULTIPLY, 1.0))
	var panel := _panel()
	panel.bind(_node, _graph)
	assert_false(panel.has_content())
	assert_false(panel.is_paging(), "there is no empty framed page to cycle")
	assert_eq(panel._pages.size(), 0)


func test_rebinding_to_a_smaller_node_stops_the_carousel() -> void:
	var ent := _spawn_entity()
	_grant_many(ent, 10)
	var panel := _panel()
	panel.bind(_node, _graph)
	assert_true(panel.is_paging())
	var bare: SkillNode = _SKILL_NODE_SCENE.instantiate()
	_graph.add_skill_node(bare)
	panel.bind(bare, _graph)
	assert_false(panel.is_paging(), "a rebind must not leave the previous node's carousel running")
	assert_eq(panel._rows.modulate.a, 1.0, "and must not leave the rows parked mid-crossfade")
