extends GutTest

## #575 / #588 — the menu's hover tooltip: a centred stack of [SlabRow]s that
## sits directly under the node it describes.
##
## Two load-bearing tests here.
##
## `test_players_never_becomes_a_real_stat` — #575 is explicit that `PLAYERS` is
## a string in the menu's own data and must not reach [StatRegistry], and the
## tempting way to render it "exactly like a real granted modifier" is to make
## it one. Since #588 the tooltip composes [SlabRow], which takes a plain string
## and a [Color], so there is not even a transient [StatDef] left in the path —
## this test is what keeps it that way.
##
## `test_a_two_line_tooltip_is_two_lines_tall` — #588's whole reason for
## existing. The previous panel carried a layout cycle (tooltip minimum read a
## `%Body` that was anchored to the tooltip, containing an autowrap [Label]) and
## settled at ~470px for two lines of text. A stack of Container-managed rows
## has no cycle to converge, and this asserts the height that proves it.

const _SCENE := preload("res://ui/frontmatter/menu_tooltip.tscn")
const _ROOT_SCENE := preload("res://ui/frontmatter/frontmatter_root.tscn")

var _tree: MenuGraph
var _tooltip: MenuTooltip


func before_each() -> void:
	_tree = MenuGraph.build()
	_tooltip = _SCENE.instantiate()
	add_child_autofree(_tooltip)


## The look table is a process-global cache of what the fan scenes author, and
## two tests below poke at a look to prove the tooltip reads it rather than
## restating it. Dropping the cache re-reads the scenes, so a poke cannot leak
## into the next test — or into another suite in the same run.
func after_each() -> void:
	FrontmatterLayout.reset_geometry()


func _bind(id: StringName) -> void:
	_tooltip.bind(FrontmatterLayout.look_of(id))


func _rows() -> Array[SlabRow]:
	var out: Array[SlabRow] = []
	for child: Node in _tooltip.get_children():
		out.append(child as SlabRow)
	return out


func _row_text() -> Array[String]:
	var out: Array[String] = []
	for row: SlabRow in _rows():
		out.append(row._label.text)
	return out


# --- the joke ---------------------------------------------------------------

func test_single_player_grants_one_player() -> void:
	_bind(MenuGraph.ID_SINGLE_PLAYER)
	assert_eq(_row_text(), [MenuTooltip.SLAB_HEADER, "PLAYERS +1"] as Array[String])


func test_multiplayer_grants_eight_players() -> void:
	_bind(MenuGraph.ID_MULTIPLAYER)
	assert_eq(_row_text(), [MenuTooltip.SLAB_HEADER, "PLAYERS +8"] as Array[String])


## The joke's text has exactly one home — the caption the node itself renders.
## Since #591 that home is `root_menu.tscn`'s slot, not [MenuGraph].
func test_the_slab_reads_the_authored_slot_rather_than_restating_it() -> void:
	var look := FrontmatterLayout.look_of(MenuGraph.ID_SINGLE_PLAYER)
	assert_eq(look.subtitle, "+1 PLAYERS", "the slot authors it sign-first")
	look.subtitle = "+3 GOATS"
	_tooltip.bind(look)
	assert_eq(_row_text(), [MenuTooltip.SLAB_HEADER, "GOATS +3"] as Array[String])


func test_a_subtitle_that_is_not_a_signed_modifier_yields_no_slab() -> void:
	var look := FrontmatterLayout.look_of(MenuGraph.ID_SINGLE_PLAYER)
	for junk: String in ["PLAYERS", "lots of players", " "]:
		look.subtitle = junk
		assert_eq(MenuTooltip.slab_for(look).size(), 0, "'%s' is not a modifier" % junk)
		assert_eq(MenuTooltip.slab_text(look), "", "'%s' renders no slab row" % junk)


## The one that matters. `PLAYERS` renders like a granted modifier and is not
## one — nothing about it may reach the stat system.
func test_players_never_becomes_a_real_stat() -> void:
	for id: StringName in [&"PLAYERS", &"players", &"Players"]:
		assert_null(StatRegistry.get_def(id), "'%s' is not a registered stat" % id)
	_bind(MenuGraph.ID_MULTIPLAYER)
	assert_eq(_rows().size(), 2, "and it still renders")
	for id: StringName in [&"PLAYERS", &"players"]:
		assert_null(StatRegistry.get_def(id), "and rendering it did not register one")


# --- the described leaves ---------------------------------------------------

func test_a_described_leaf_shows_its_title_and_its_line() -> void:
	_bind(MenuGraph.ID_NEW_GAME)
	assert_eq(_row_text(), ["NEW GAME", "Begin something new."] as Array[String])


## Every one of #575's seven lines, checked against the tree that has to carry
## them — a leaf added without a description shows up here, not in play.
func test_every_leaf_in_the_tree_has_something_to_say() -> void:
	for id in _tree.ids():
		if not _tree.is_leaf(id):
			continue
		assert_true(MenuTooltip.has_content(FrontmatterLayout.look_of(id)),
				"%s has a tooltip" % id)
		assert_ne(MenuTooltip.describe(id), "", "%s has a description" % id)
	assert_eq(
		MenuTooltip.describe(MenuGraph.ID_HOST), "Open a game for others to join.",
		"verbatim from #575",
	)


# --- and what shows nothing -------------------------------------------------

## #575's third acceptance bullet, in the form that does not contradict its
## first: what suppresses a tooltip is having nothing to say, and the ROOT is
## the node that has children and no content.
func test_a_node_with_children_and_no_content_shows_no_rows() -> void:
	_bind(MenuGraph.ID_ROOT)
	assert_eq(_rows().size(), 0)
	assert_false(MenuTooltip.has_content(FrontmatterLayout.look_of(MenuGraph.ID_ROOT)))
	assert_almost_eq(_tooltip.modulate.a, 0.0, 0.0001, "it rests, it does not hide")


func test_binding_null_empties_it() -> void:
	_bind(MenuGraph.ID_EXIT)
	assert_eq(_rows().size(), 2)
	_tooltip.bind(null)
	assert_eq(_rows().size(), 0)
	assert_null(_tooltip.look)


## #588: a hidden [Control] skips layout, which is what broke size convergence.
## The rest state is transparent, never invisible — at every step.
func test_the_tooltip_is_never_hidden() -> void:
	assert_true(_tooltip.visible, "fresh")
	_bind(MenuGraph.ID_ROOT)
	assert_true(_tooltip.visible, "nothing to say")
	_tooltip.bind(null)
	assert_true(_tooltip.visible, "unbound")
	_bind(MenuGraph.ID_EXIT)
	assert_true(_tooltip.visible, "bound")


func test_rebinding_replaces_the_content_rather_than_stacking_it() -> void:
	_bind(MenuGraph.ID_SINGLE_PLAYER)
	_bind(MenuGraph.ID_MULTIPLAYER)
	assert_eq(_row_text(), [MenuTooltip.SLAB_HEADER, "PLAYERS +8"] as Array[String])
	_bind(MenuGraph.ID_OPTIONS)
	assert_eq(_row_text(), ["OPTIONS", "Tune the experience."] as Array[String])


# --- the size, which is the whole point of #588 -----------------------------

## Was ~470px before the stack replaced the panel.
func test_a_two_line_tooltip_is_two_lines_tall() -> void:
	_bind(MenuGraph.ID_LOCAL)
	assert_eq(_row_text(), ["LOCAL", "Same device, same screen."] as Array[String])
	assert_lt(_tooltip.size.y, 120.0, "two rows, not a wall of text")


func test_the_stack_grows_with_its_content() -> void:
	_bind(MenuGraph.ID_LOCAL)
	var two_rows := _tooltip.size.y
	_bind(MenuGraph.ID_SINGLE_PLAYER)  # header + slab + no description
	var with_slab := _tooltip.size.y
	assert_eq(_rows().size(), 2)
	assert_almost_eq(with_slab, two_rows, 4.0, "two rows either way")
	_tooltip.bind(null)
	assert_lt(_tooltip.size.y, two_rows, "and it shrinks back when emptied")


# --- identity and reveal ----------------------------------------------------

## The tooltip takes the node's own archetype colour, through #569's map — not
## a second table of menu colours.
func test_the_tooltip_is_tinted_by_the_node_s_archetype() -> void:
	for id: StringName in [MenuGraph.ID_SINGLE_PLAYER, MenuGraph.ID_OPTIONS, MenuGraph.ID_EXIT]:
		var look := FrontmatterLayout.look_of(id)
		var expected := MenuNodeView.archetype_for(look.archetype).color
		assert_eq(MenuTooltip.tint_for(look), expected, "%s" % id)
		_bind(id)
		for row: SlabRow in _rows():
			assert_eq(row._slab.tint_color, expected, "%s row" % id)


func test_set_progress_fades_and_grows_it() -> void:
	_bind(MenuGraph.ID_EXIT)
	_tooltip.set_progress(0.0)
	assert_almost_eq(_tooltip.modulate.a, 0.0, 0.0001)
	assert_almost_eq(_tooltip.scale.x, _tooltip.start_scale, 0.0001)
	_tooltip.set_progress(1.0)
	assert_almost_eq(_tooltip.modulate.a, 1.0, 0.0001)
	assert_almost_eq(_tooltip.scale.x, 1.0, 0.0001)


## The rows themselves are fully revealed — the STACK owns the fade, so a row
## still resting at `t = 0` would be an invisible tooltip.
func test_the_rows_are_revealed_by_bind() -> void:
	_bind(MenuGraph.ID_LOCAL)
	for row: SlabRow in _rows():
		assert_almost_eq(row.modulate.a, 1.0, 0.0001)
		assert_almost_eq(row.scale.x, 1.0, 0.0001)


# --- placement (#588: centred, directly under the node) ---------------------

class _Placed extends RefCounted:
	var root: FrontmatterRoot
	var tooltip: MenuTooltip

	func node_screen_x(id: StringName) -> float:
		return (root.get_viewport_transform() * root.view_for(id).global_position).x

	func node_screen_y(id: StringName) -> float:
		return (root.get_viewport_transform() * root.view_for(id).global_position).y

	func centre_x() -> float:
		return tooltip.position.x + tooltip.size.x * 0.5


func _placed() -> _Placed:
	var out := _Placed.new()
	out.root = _ROOT_SCENE.instantiate()
	add_child_autofree(out.root)
	out.root.reduce_motion = true
	out.tooltip = out.root._tooltip
	return out


## The acceptance, three times over: the stack's horizontal centre is its node's
## screen x — at rest, mid-travel, and fully revealed. The tooltip is placed
## every frame it is up precisely because the node is still moving.
func test_the_stack_is_centred_on_its_node() -> void:
	var p := _placed()
	var id := MenuGraph.ID_SINGLE_PLAYER
	p.root.set_hovered(id)
	p.root._place_tooltip(id)
	assert_almost_eq(p.centre_x(), p.node_screen_x(id), 1.0, "at rest")

	p.root.focus(id)
	p.root.set_progress(0.5)
	p.root._place_tooltip(id)
	assert_almost_eq(p.centre_x(), p.node_screen_x(id), 1.0, "mid-flight")

	p.root.set_progress(1.0)
	p.tooltip.set_progress(1.0)
	p.root._place_tooltip(id)
	assert_almost_eq(p.centre_x(), p.node_screen_x(id), 1.0, "revealed")


func test_the_stack_sits_below_offset_beneath_its_node() -> void:
	var p := _placed()
	var id := MenuGraph.ID_EXIT
	p.root.tooltip_below_offset = 60.0
	p.root.set_hovered(id)
	p.root._place_tooltip(id)
	assert_almost_eq(p.tooltip.position.y - p.node_screen_y(id), 60.0, 0.001)


## Centred means the pivot is centred too, or a partially revealed stack drifts
## left as it scales about its top-left corner.
func test_the_scale_pivot_is_centred() -> void:
	_bind(MenuGraph.ID_LOCAL)
	assert_almost_eq(_tooltip.pivot_offset.x, _tooltip.size.x * 0.5, 0.001)
	assert_almost_eq(_tooltip.pivot_offset.y, _tooltip.size.y * 0.5, 0.001)
