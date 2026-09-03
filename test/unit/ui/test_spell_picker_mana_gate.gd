extends GutTest

## #743 — the spell picker greys a spell the entity can't afford (mana) while
## keeping it clickable, floats "GEEN MANA MEER" through [signal
## Events.ui_action_denied] on a click instead of selecting it, and regreys
## LIVE when a cast drops mana below another spell's cost — no rebuild, no
## reselect. Complements test_denial_toast.gd (the node-anchored sibling
## path); this pins the widget-anchored one Events.ui_action_denied adds.
##
## Deliberately builds its own SpellDefs with arbitrary costs rather than
## reading a shipped SpellCatalog entry — the owner's mana numbers are tuning,
## not something a test should pin (.claude/rules — "owner tunes, agents
## test").
##
## [b]#728 added the picker's second clickable gate[/b], and it shares this
## file because it shares the whole mechanism: grey-but-clickable, denial on
## press, one [constant FloaterDirector._DENIAL_TEXTS] row. The mana tests keep
## `min_degree = 0` over a one-node territory so the caster gate is always MET
## and the mana axis stays isolated; the caster tests at the bottom raise
## `min_degree` past what the territory can offer and assert the other reason
## code. That the two gates are separately observable is the point — one is
## fixed by waiting, the other only by growing territory.

const _BAR_SCENE := preload("res://ui/spell_picker_bar/spell_picker_bar.tscn")
const _DEFAULT_BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")

var _bar: SpellPickerBar
var _graph: Graph
var _node: SkillNode
var _entity: Entity
var _book: SpellBook
var _cheap_spell: SpellDef
var _pricey_spell: SpellDef
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
	# Pin a known, arbitrary starting pool rather than whatever the authored
	# board ships — the exact number is a fixture concern, not owner tuning.
	# MUST run after add_child: Entity._ready() tops every pool to full, which
	# would silently clobber a `.current` set beforehand.
	_entity.stat_board.mana.current = 6.0

	_cheap_spell = SpellDef.new()
	_cheap_spell.name = "Cheap"
	_cheap_spell.mana_cost = 5
	_cheap_spell.min_degree = 0

	_pricey_spell = SpellDef.new()
	_pricey_spell.name = "Pricey"
	_pricey_spell.mana_cost = 8
	_pricey_spell.min_degree = 0

	_book = SpellBook.new()
	_book.learn(_cheap_spell)
	_book.learn(_pricey_spell)

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


func test_unaffordable_spell_greys_but_stays_clickable() -> void:
	var btn := _btn(_pricey_spell)
	assert_not_null(btn)
	assert_false(btn.disabled, "mana gate must not use `disabled` — a disabled Button swallows the click the denial needs")


func test_affordable_spell_is_not_greyed() -> void:
	var btn := _btn(_cheap_spell)
	assert_false(btn.disabled)
	# Affordable and castable (source null never gates min_degree) — toggle_mode
	# stays on, same as before #743 touched anything.
	assert_true(btn.toggle_mode)


func test_click_on_unaffordable_spell_denies_and_does_not_select() -> void:
	var selected: Array[SpellDef] = []
	_bar.spell_selected.connect(func(s: SpellDef): selected.append(s))

	_btn(_pricey_spell)._on_pressed()

	assert_eq(selected.size(), 0, "an unaffordable pick must never emit spell_selected")
	assert_eq(_denials.size(), 1)
	assert_eq(_denials[0]["reason"], "spell_denied_no_mana")
	assert_true(is_instance_valid(_denials[0]["anchor"]), "the denial must anchor at a live node")


func test_click_on_affordable_spell_selects_and_denies_nothing() -> void:
	var selected: Array[SpellDef] = []
	_bar.spell_selected.connect(func(s: SpellDef): selected.append(s))

	_btn(_cheap_spell)._on_pressed()

	assert_eq(selected, [_cheap_spell])
	assert_eq(_denials.size(), 0)


func test_unaffordable_button_is_not_toggle_capable() -> void:
	# Cheap (affordable, unselected) stays toggle-capable — the normal click
	# flow is untouched by #743.
	assert_true(_btn(_cheap_spell).toggle_mode)
	# Pricey (unaffordable, unselected) is NOT. This is the actual fix: Godot's
	# ButtonGroup exclusivity (unpress the sibling, commit button_pressed on
	# the clicked one) runs synchronously inside native click processing,
	# before any signal handler gets a chance to veto it — a toggle_mode=true
	# unaffordable button would steal the highlight from the real selection
	# with nothing able to hand it back. toggle_mode=false means Godot's own
	# click handling never touches button_pressed/the group for this button at
	# all — nothing to steal, nothing to revert.
	assert_false(_btn(_pricey_spell).toggle_mode)


func test_casting_drops_mana_and_regreys_live_without_rebuild_or_reselect() -> void:
	var cheap_btn := _btn(_cheap_spell)
	var pricey_btn := _btn(_pricey_spell)
	assert_false(pricey_btn.disabled)
	# Sanity: pricey (cost 8) is unaffordable at mana 6, cheap (cost 5) is not.
	assert_true(cheap_btn.toggle_mode)

	# Raise mana above both costs, then drop it via the pool's own transfer
	# method (mirrors how BattleSystem._commit pays for a cast:
	# `mana_pool.deplete(...)`) so `current_changed` fires exactly as it would
	# from a real launch — no bar rebuild, no reselect in between.
	_entity.stat_board.mana.current = 9.0
	assert_true(cheap_btn.toggle_mode, "affordable again above both costs")

	_entity.stat_board.mana.deplete(4.0)  # 9 -> 5: now only the cheap spell fits

	assert_true(cheap_btn.toggle_mode, "still affordable at exactly its cost")
	assert_false(pricey_btn.toggle_mode, "regreyed live off the pool signal, no rebuild/reselect")


func test_selected_spell_keeps_its_highlight_after_becoming_unaffordable() -> void:
	var cheap_btn := _btn(_cheap_spell)
	# Select the cheap spell while it's still affordable — the same
	# button_pressed + toggled sequence test_loot_picker.gd uses to drive a
	# real ButtonGroup commit from script (a plain `pressed.emit()` never
	# touches button_pressed at all, only the native click path does).
	cheap_btn.button_pressed = true
	cheap_btn.toggled.emit(true)
	assert_true(cheap_btn.button_pressed)

	# Drain mana below the SELECTED spell's own cost via a real cast-shaped
	# deplete — the model (BattleSystem.selected_spell, mirrored here by the
	# fact nothing reselected) never changed, so the view must not silently
	# desync from it.
	_entity.stat_board.mana.deplete(3.0)  # 6 -> 3, below the cheap spell's cost of 5

	assert_true(cheap_btn.button_pressed, "the highlight must survive its own spell going unaffordable")
	assert_true(cheap_btn.toggle_mode, "kept toggle-capable so the button_pressed carve-out in _refresh_toggle_mode holds")

	# Re-clicking the now-unaffordable-but-still-selected spell is a
	# legitimate "why can't I recast this" moment — it must re-float the
	# denial, not silently no-op.
	cheap_btn._on_pressed()
	assert_eq(_denials.size(), 1)
	assert_eq(_denials[0]["reason"], "spell_denied_no_mana")


# ── #728: the caster gate, the picker's other clickable denial ─────────────

## A spell no owned node clears the min_degree for: the territory is one node,
## so its owned-subgraph degree is 0 and nothing satisfies a degree-2 spell.
func _uncastable_spell() -> SpellDef:
	var spell := SpellDef.new()
	spell.name = "Needs a hub"
	spell.mana_cost = 1  # affordable, so only the caster gate can deny it
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
			"structural denial, distinct from the mana one")
	assert_not_null(_denials[0]["anchor"], "anchored at the button, not at a node")
	assert_eq(picked.size(), 0, "and it selects nothing")


## The two dead ends must stay separately observable — a spell that is both
## unaffordable AND uncastable reports the one the player cannot fix by
## waiting a turn.
func test_the_caster_denial_outranks_the_mana_denial() -> void:
	var both := _uncastable_spell()
	both.mana_cost = 99
	_book.learn(both)
	_bar.update_gating_context(_entity)

	_btn(both)._on_pressed()

	assert_eq(_denials.size(), 1)
	assert_eq(_denials[0]["reason"], "spell_denied_no_caster")


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
