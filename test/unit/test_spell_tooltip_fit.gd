extends GutTest

## The floating [SpellTooltip] is a free Control: nothing re-fits it for us, and
## its autowrap Labels measure their height by wrapping at the panel's *current*
## width. Before the fit pass it settled at ~4762px tall — a viewport-height
## tooltip that then stuck for every spell hovered afterwards. Guard both halves:
## it is never shown taller than its content, and it shrinks between spells.

const _TOOLTIP := preload("res://ui/spell_tooltip/spell_tooltip.tscn")

# Longest and shortest authored descriptions — the height spread is the point.
const _TALL := "res://attack/spell/defs/leafblower.tres"
const _SHORT := "res://attack/spell/defs/spark.tres"

# show_for() settles the layout over two frames before it fades in; wait past it.
# Note: a single wait_frames(4) does NOT yield four real idle frames here — the
# awaited frames have to be taken one at a time for the layout to advance.
const _SETTLE_FRAMES: int = 5


func test_tooltip_is_never_shown_taller_than_its_content() -> void:
	var tt: SpellTooltip = _TOOLTIP.instantiate()
	add_child_autofree(tt)
	await wait_frames(2)

	for path in [_TALL, _SHORT, _TALL]:
		tt.show_for(load(path) as SpellDef, null)
		for _i in _SETTLE_FRAMES:
			await wait_frames(1)
		assert_true(tt.visible, "%s: should be showing" % path)
		assert_almost_eq(tt.modulate.a, 1.0, 0.01, "%s: stuck faded out" % path)
		assert_almost_eq(
			tt.size.y, tt.get_combined_minimum_size().y, 1.0,
			"%s: tooltip taller than its content" % path
		)


func test_tooltip_shrinks_when_a_shorter_spell_is_hovered() -> void:
	var tt: SpellTooltip = _TOOLTIP.instantiate()
	add_child_autofree(tt)
	await wait_frames(2)

	tt.show_for(load(_TALL) as SpellDef, null)
	for _i in _SETTLE_FRAMES:
		await wait_frames(1)
	var tall_height := tt.size.y

	tt.show_for(load(_SHORT) as SpellDef, null)
	for _i in _SETTLE_FRAMES:
		await wait_frames(1)
	assert_lt(tt.size.y, tall_height, "tooltip kept the taller spell's height")


func test_tooltip_renders_its_content_through_scene_components() -> void:
	var tt: SpellTooltip = _TOOLTIP.instantiate()
	add_child_autofree(tt)
	await wait_frames(2)

	var spell := load(_TALL) as SpellDef
	tt.show_for(spell, null)
	for _i in _SETTLE_FRAMES:
		await wait_frames(1)

	var header: PanelHeader = tt.get_node("%Header")
	assert_eq(header.header, spell.name.to_upper(), "header should carry the spell name")
	assert_string_contains(header.subheader, str(spell.min_degree))
	assert_string_contains(tt.get_node("%ManaLabel").text, str(spell.mana_cost))

	var rows := tt.get_node("%StatsGrid").get_children()
	assert_gt(rows.size(), 0, "stat rows should be built")
	for row in rows:
		assert_is(row, SpellStatRow, "rows must be the row scene, not code-built Labels")
