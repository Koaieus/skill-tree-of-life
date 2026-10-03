extends GutTest

## #728 — the spell picker greys a spell no owned node can cast (min_degree over
## the whole territory) while keeping it clickable, floats "GEEN CASTER" through
## [signal Events.ui_action_denied] on a click instead of selecting it, and
## ungreys once the territory grows — no reselect. Complements
## test_denial_toast.gd (the node-anchored sibling path); this pins the
## widget-anchored one Events.ui_action_denied adds.
##
## Builds its own SpellDefs rather than reading a shipped SpellCatalog entry —
## the authored min_degree values are tuning, not something a test should pin.

const _BAR_SCENE := preload("res://ui/spell_picker_bar/spell_picker_bar.tscn")
const _DEFAULT_BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")

var _bar: SpellPickerBar
var _graph: Graph
var _node: SkillNode
var _entity: Entity
var _book: SpellBook
var _denials: Array


func before_each() -> void:
	# A one-node territory: #728 reads the eligible-caster set off
	# `attacker.navigator`, so an entity with no graph has no caster for
	# ANY spell and every press would toast the wrong reason.
	_graph = _GRAPH_SCENE.instantiate() as Graph
	add_child_autofree(_graph)
	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.add_skill_node(_node)

	_entity = Entity.new()
	_entity.display_name = "Caster"
	_entity.stat_board = _DEFAULT_BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)
	autofree(_entity)
	await get_tree().process_frame  # Entity._ready wires the navigator

	var alloc := AllocationSystem.new()
	alloc.graph = _graph
	add_child_autofree(alloc)
	alloc.force_allocate(_entity, _node)
	_book = SpellBook.new()

	_bar = _BAR_SCENE.instantiate() as SpellPickerBar
	add_child_autofree(_bar)
	_bar.bind_spellbook(_book)
	_bar.update_gating_context(_entity)

	_denials = []
	Events.ui_action_denied.connect(_on_ui_action_denied)


func after_each() -> void:
	if Events.ui_action_denied.is_connected(_on_ui_action_denied):
		Events.ui_action_denied.disconnect(_on_ui_action_denied)


func _on_ui_action_denied(anchor: Node2D, reason: String) -> void:
	_denials.append({"anchor": anchor, "reason": reason})


## Skips children already queued for deletion. [method SpellPickerBar._rebuild]
## `queue_free()`s the old row and adds the new one in the same frame, so both
## are in `get_children()` until the frame ends — without this guard a test
## that learns a spell mid-test reads the STALE button, which no
## [method SpellPickerBar.update_gating_context] will ever touch again.
func _btn(spell: SpellDef) -> SpellPickerButton:
	for child in _bar.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is SpellPickerButton and (child as SpellPickerButton).spell == spell:
			return child as SpellPickerButton
	return null


## A spell no owned node clears the min_degree for: the territory is one node,
## so its owned-subgraph degree is 0 and nothing satisfies a degree-2 spell.
func _uncastable_spell() -> SpellDef:
	var spell := SpellDef.new()
	spell.name = "Needs a hub"
	spell.min_degree = 2
	return spell


func test_a_spell_no_owned_node_can_cast_greys_but_stays_clickable() -> void:
	var uncastable := _uncastable_spell()
	_book.learn(uncastable)   # membership_changed rebuilds the row on its own
	_bar.update_gating_context(_entity)
	var btn := _btn(uncastable)
	assert_not_null(btn)
	assert_false(btn.disabled,
			"grey, not disabled — a disabled Button swallows the click the toast needs")


func test_pressing_it_toasts_no_caster_at_the_button_and_selects_nothing() -> void:
	var uncastable := _uncastable_spell()
	_book.learn(uncastable)   # membership_changed rebuilds the row on its own
	_bar.update_gating_context(_entity)
	var picked: Array = []
	_bar.spell_selected.connect(func(s: SpellDef) -> void: picked.append(s))

	_btn(uncastable)._on_pressed()

	assert_eq(_denials.size(), 1)
	assert_eq(_denials[0]["reason"], "spell_denied_no_caster",
			"the caster gate's own reason code")
	assert_not_null(_denials[0]["anchor"], "anchored at the button, not at a node")
	assert_eq(picked.size(), 0, "and it selects nothing")


## The gate is a TERRITORY question now, not a source one: growing the
## territory must make the spell castable with no reselect.
func test_growing_the_territory_ungreys_a_spell_that_had_no_caster() -> void:
	var uncastable := _uncastable_spell()
	_book.learn(uncastable)   # membership_changed rebuilds the row on its own
	_bar.update_gating_context(_entity)
	_btn(uncastable)._on_pressed()
	assert_eq(_denials.size(), 1, "precondition: denied while the territory is one node")

	# A path of three: the middle node now has owned-subgraph degree 2.
	var alloc := _graph.get_node_or_null(^"GrowthAlloc") as AllocationSystem
	if alloc == null:
		alloc = AllocationSystem.new()
		alloc.name = "GrowthAlloc"
		alloc.graph = _graph
		_graph.add_child(alloc)
	for _i in 2:
		var extra := _SKILL_NODE_SCENE.instantiate() as SkillNode
		_graph.add_skill_node(extra)
		# Allocate BEFORE edging: an EntityNavigator mirrors owned nodes only,
		# so an edge announced while its far end is still unowned is dropped.
		alloc.force_allocate(_entity, extra)
		_graph.add_edge(_node, extra)

	_bar.update_gating_context(_entity)
	_denials.clear()
	_btn(uncastable)._on_pressed()

	assert_eq(_denials.size(), 0, "the hub now clears min_degree 2")
