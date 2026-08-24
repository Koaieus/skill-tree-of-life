extends GutTest

## #575 — leaf tooltips and the `+1 / +8 PLAYERS` joke slab.
##
## The load-bearing test here is `test_players_never_becomes_a_real_stat`. #575
## is explicit that `PLAYERS` is a string in the menu's own data and must not
## reach [StatRegistry], and the tempting way to render it "exactly like a real
## granted modifier" is to make it one. That test is what stops the joke from
## quietly acquiring a StatDef resource, a registry entry and a board slot.
##
## The tooltip is driven through [method MenuTooltip.bind] and read back off the
## shipped tooltip-fan rows it composes, so a fork of those rows (which #575
## forbids) shows up as these assertions reading the wrong nodes rather than as
## a diff nobody looks at.

const _SCENE := preload("res://ui/frontmatter/menu_tooltip.tscn")

var _tree: MenuGraph
var _tooltip: MenuTooltip


func before_each() -> void:
	_tree = MenuGraph.build()
	_tooltip = _SCENE.instantiate()
	add_child_autofree(_tooltip)


func _bind(id: StringName) -> void:
	_tooltip.bind(_tree.get_item(id))


func _rows() -> Array[Node]:
	return (_tooltip.get_node("%Rows") as VBoxContainer).get_children()


func _row_text() -> Array[String]:
	var out: Array[String] = []
	for row: Node in _rows():
		out.append("%s %s" % [
			(row.get_node("%NameLabel") as Label).text,
			(row.get_node("%ValueLabel") as Label).text,
		])
	return out


func _header_text() -> String:
	return (_tooltip.get_node("%Header") as PanelHeader).header


func _description_text() -> String:
	return (_tooltip.get_node("%Description") as Label).text


# --- the joke ---------------------------------------------------------------

func test_single_player_grants_one_player() -> void:
	_bind(MenuGraph.ID_SINGLE_PLAYER)
	assert_true(_tooltip.visible)
	assert_eq(_row_text(), ["PLAYERS +1"] as Array[String])
	assert_eq(_header_text(), MenuTooltip.SLAB_HEADER)
	assert_eq(_description_text(), "", "the joke stands on its own")


func test_multiplayer_grants_eight_players() -> void:
	_bind(MenuGraph.ID_MULTIPLAYER)
	assert_eq(_row_text(), ["PLAYERS +8"] as Array[String])
	assert_eq(_header_text(), MenuTooltip.SLAB_HEADER)


## The joke's text has exactly one home — the caption the node itself renders.
func test_the_slab_reads_the_model_rather_than_restating_it() -> void:
	var item := _tree.get_item(MenuGraph.ID_SINGLE_PLAYER)
	assert_eq(item.subtitle, "+1 PLAYERS", "the model still authors it sign-first")
	item.subtitle = "+3 GOATS"
	_tooltip.bind(item)
	assert_eq(_row_text(), ["GOATS +3"] as Array[String])


func test_a_subtitle_that_is_not_a_signed_modifier_yields_no_slab() -> void:
	var item := _tree.get_item(MenuGraph.ID_SINGLE_PLAYER)
	for junk: String in ["PLAYERS", "lots of players", " "]:
		item.subtitle = junk
		assert_eq(MenuTooltip.slab_for(item).size(), 0, "'%s' is not a modifier" % junk)


## The one that matters. `PLAYERS` renders like a granted modifier and is not
## one — nothing about it may reach the stat system.
func test_players_never_becomes_a_real_stat() -> void:
	for id: StringName in [&"PLAYERS", &"players", &"Players"]:
		assert_null(StatRegistry.get_def(id), "'%s' is not a registered stat" % id)
	_bind(MenuGraph.ID_MULTIPLAYER)
	assert_eq(_rows().size(), 1, "and it still renders")
	for id: StringName in [&"PLAYERS", &"players"]:
		assert_null(StatRegistry.get_def(id), "and rendering it did not register one")


# --- the described leaves ---------------------------------------------------

func test_a_described_leaf_shows_its_line_and_no_slab() -> void:
	_bind(MenuGraph.ID_NEW_GAME)
	assert_true(_tooltip.visible)
	assert_eq(_description_text(), "Begin something new.")
	assert_eq(_rows().size(), 0, "no slab on a plain leaf")
	assert_eq(_header_text(), "NEW GAME", "the tooltip names its subject")


## Every one of #575's seven lines, checked against the tree that has to carry
## them — a leaf added without a description shows up here, not in play.
func test_every_leaf_in_the_tree_has_something_to_say() -> void:
	for id in _tree.ids():
		if not _tree.is_leaf(id):
			continue
		var item := _tree.get_item(id)
		assert_true(MenuTooltip.has_content(item), "%s has a tooltip" % id)
		assert_ne(MenuTooltip.describe(id), "", "%s has a description" % id)
	assert_eq(
		MenuTooltip.describe(MenuGraph.ID_HOST), "Open a game for others to join.",
		"verbatim from #575",
	)


# --- and what shows nothing -------------------------------------------------

## #575's third acceptance bullet, in the form that does not contradict its
## first: what suppresses a tooltip is having nothing to say, and the ROOT is
## the node that has children and no content.
func test_a_node_with_children_and_no_content_shows_no_tooltip() -> void:
	_bind(MenuGraph.ID_ROOT)
	assert_false(_tooltip.visible)
	assert_false(MenuTooltip.has_content(_tree.get_item(MenuGraph.ID_ROOT)))
	assert_eq(_rows().size(), 0)


func test_binding_null_hides_it() -> void:
	_bind(MenuGraph.ID_EXIT)
	assert_true(_tooltip.visible)
	_tooltip.bind(null)
	assert_false(_tooltip.visible)
	assert_null(_tooltip.item)


func test_rebinding_replaces_the_content_rather_than_stacking_it() -> void:
	_bind(MenuGraph.ID_SINGLE_PLAYER)
	_bind(MenuGraph.ID_MULTIPLAYER)
	assert_eq(_rows().size(), 1, "one slab, not two")
	_bind(MenuGraph.ID_OPTIONS)
	assert_eq(_rows().size(), 0, "and a described leaf clears it")
	assert_eq(_description_text(), "Tune the experience.")


# --- identity and reveal ----------------------------------------------------

## The tooltip takes the node's own archetype colour, through #569's map — not
## a second table of menu colours.
func test_the_tooltip_is_tinted_by_the_node_s_archetype() -> void:
	for id: StringName in [MenuGraph.ID_SINGLE_PLAYER, MenuGraph.ID_OPTIONS, MenuGraph.ID_EXIT]:
		var item := _tree.get_item(id)
		var expected := MenuNodeView.archetype_for(item.archetype).color
		assert_eq(MenuTooltip.tint_for(item), expected, "%s" % id)
		_bind(id)
		assert_eq((_tooltip.get_node("%Slab") as SlabPanel).tint_color, expected, "%s slab" % id)


func test_set_progress_fades_and_grows_it() -> void:
	_bind(MenuGraph.ID_EXIT)
	_tooltip.set_progress(0.0)
	assert_almost_eq(_tooltip.modulate.a, 0.0, 0.0001)
	assert_almost_eq(_tooltip.scale.x, _tooltip.start_scale, 0.0001)
	_tooltip.set_progress(1.0)
	assert_almost_eq(_tooltip.modulate.a, 1.0, 0.0001)
	assert_almost_eq(_tooltip.scale.x, 1.0, 0.0001)
