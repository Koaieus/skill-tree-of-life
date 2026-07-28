extends GutTest

## Tooltip V2 (#226/#227) — the ROOTS acceptance test. Covers: one [ModSlabRow]
## per flattened modifier leaf (composite expanded, addon-granted included
## for free via `node.modifiers`), one "Grants <spell>" line per granted
## [SpellGrant] (from [method SkillNode.get_node_effects], sourced above the
## slabs), no header/legend/frame, and rows driven via `set_progress` with a
## per-index stagger (`play_entry` never called — it doesn't exist on
## [ModSlabRow] any more). Instantiated standalone — no [TooltipFan] present.

const _ROOT_SCENE := preload("res://ui/tooltip_fan/panels/granted_modifiers_root.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _node: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_node.name = "N0"
	_graph.skill_nodes_container.add_child(_node)


func _make_modifier(op: StatModifier.Operation, value: float, stat_id: StringName = &"armor") -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = op
	m.value = value
	return m


func test_bind_renders_one_mod_slab_row_per_flattened_leaf() -> void:
	var str_mod := _make_modifier(StatModifier.Operation.ADD_BASE, 4.0, &"strength")
	var composite := CompositeStatModifier.new()
	var child_a := _make_modifier(StatModifier.Operation.ADD_BASE, 2.0, &"dexterity")
	var child_b := _make_modifier(StatModifier.Operation.INCREASE, 20.0, &"armor")
	composite.children = [child_a, child_b]
	_node.modifiers = [str_mod, composite]

	var root := _ROOT_SCENE.instantiate() as GrantedModifiersRoot
	add_child_autofree(root)
	root.bind(_node)

	var rows := _mod_slab_rows(root)
	assert_eq(rows.size(), 3, "1 leaf + a 2-child composite flattened = 3 rows")
	var texts := rows.map(func(r): return r._label.text)
	assert_true(texts.has(str_mod.format()))
	assert_true(texts.has(child_a.format()))
	assert_true(texts.has(child_b.format()))


func test_addon_granted_modifiers_are_included_via_node_modifiers() -> void:
	var anchor := _node.get_node_or_null("Visuals/AddonAnchor")
	assert_not_null(anchor, "fixture must have an AddonAnchor to attach the addon under")
	var addon := SkillNodeAddon.new()
	var granted := _make_modifier(StatModifier.Operation.ADD_BONUS, 5.0, &"armor")
	addon.entity_modifiers = [granted]
	anchor.add_child(addon)
	await get_tree().process_frame

	assert_true(_node.modifiers.has(granted), "SkillNode._on_addon_added routed the addon's entity_modifiers onto node.modifiers")

	var root := _ROOT_SCENE.instantiate() as GrantedModifiersRoot
	add_child_autofree(root)
	root.bind(_node)

	var rows := _mod_slab_rows(root)
	var texts := rows.map(func(r): return r._label.text)
	assert_true(texts.has(granted.format()), "addon-granted modifier renders as its own row")
	addon.queue_free()


func test_spell_grant_renders_above_the_modifier_slabs_in_keystone_gold() -> void:
	var spell_def := SpellDef.new()
	spell_def.name = "Emberlance"
	var grant := SpellGrant.new()
	grant.spell_def = spell_def
	_node.effects = [grant]
	_node.modifiers = [_make_modifier(StatModifier.Operation.ADD_BASE, 4.0, &"strength")]

	var root := _ROOT_SCENE.instantiate() as GrantedModifiersRoot
	add_child_autofree(root)
	root.bind(_node)

	var rows := root._rows.get_children()
	assert_eq(rows.size(), 2, "1 spell line + 1 mod row")
	assert_true(rows[0] is Label, "spell-grant line is the first row")
	assert_eq((rows[0] as Label).text, "Grants Emberlance")
	var tint: Color = (rows[0] as Label).modulate
	assert_eq(Color(tint.r, tint.g, tint.b), Color(0.95, 0.85, 0.55), "keystone gold, not an operator tint")
	assert_true(rows[1] is ModSlabRow, "modifier slab sits below the spell line")


func test_spell_grant_with_no_spell_def_is_skipped() -> void:
	var grant := SpellGrant.new()
	grant.spell_def = null
	_node.effects = [grant]

	var root := _ROOT_SCENE.instantiate() as GrantedModifiersRoot
	add_child_autofree(root)
	root.bind(_node)

	assert_eq(root._rows.get_children().size(), 0)


func test_bind_adds_no_header_no_legend_no_frame() -> void:
	_node.modifiers = [_make_modifier(StatModifier.Operation.ADD_BASE, 1.0, &"strength")]
	var root := _ROOT_SCENE.instantiate() as GrantedModifiersRoot
	add_child_autofree(root)
	root.bind(_node)

	for child in root.get_children():
		assert_ne(String(child.name), "Header")
	assert_null(root.get_node_or_null("Legend"))
	# No panel/frame Control anywhere in the tree — every child is either the
	# %Rows container or a bare content row (Label / ModSlabRow), never a
	# GlassPanel/HoloPanel skin.
	for child in root.get_children():
		assert_false(child is GlassPanel or child is HoloPanel, "no containing panel by design")


func test_rows_rest_at_zero_and_are_driven_via_set_progress_stagger() -> void:
	_node.modifiers = [
		_make_modifier(StatModifier.Operation.ADD_BASE, 1.0, &"strength"),
		_make_modifier(StatModifier.Operation.ADD_BASE, 1.0, &"dexterity"),
	]
	var root := _ROOT_SCENE.instantiate() as GrantedModifiersRoot
	add_child_autofree(root)
	root.bind(_node)

	var rows := _mod_slab_rows(root)
	assert_eq(rows.size(), 2)
	for r in rows:
		assert_almost_eq(r.modulate.a, 0.0, 0.001, "nothing sits at full alpha at rest")

	root._set_progress(1.0)
	# Stagger caps at _ROW_STAGGER_CAP < 1.0, so progress == 1.0 fully reveals
	# every row regardless of index.
	for r in rows:
		assert_almost_eq(r.modulate.a, 1.0, 0.001)

	root._set_progress(0.05)
	assert_true(rows[0].modulate.a > rows[1].modulate.a, "earlier row is ahead of a later one mid-reveal (per-index stagger)")


func test_adding_rows_grows_the_stack_downward_only() -> void:
	_node.modifiers = [_make_modifier(StatModifier.Operation.ADD_BASE, 1.0, &"strength")]
	var root := _ROOT_SCENE.instantiate() as GrantedModifiersRoot
	add_child_autofree(root)
	root.bind(_node)
	var top_before: float = root.position.y

	_node.modifiers = [
		_make_modifier(StatModifier.Operation.ADD_BASE, 1.0, &"strength"),
		_make_modifier(StatModifier.Operation.ADD_BASE, 1.0, &"dexterity"),
		_make_modifier(StatModifier.Operation.ADD_BASE, 1.0, &"constitution"),
	]
	root.bind(_node)

	assert_almost_eq(root.position.y, top_before, 0.001, "the root itself never moves when rows are added")
	assert_eq(root._rows.alignment, BoxContainer.ALIGNMENT_BEGIN, "VBoxContainer stacks top-down — growth is downward only")


func _mod_slab_rows(root: GrantedModifiersRoot) -> Array:
	var out: Array = []
	for child in root._rows.get_children():
		if child is ModSlabRow:
			out.append(child)
	return out
