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
	var mine := _spawn_entity()
	var enemy := _spawn_entity()
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
