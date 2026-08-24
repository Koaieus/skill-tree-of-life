@tool
class_name MenuTooltip
extends Control

## The stat-block a menu node shows when you point at it (#567 / #575) — a
## one-line description for most of them, and for SINGLE PLAYER / MULTIPLAYER
## the `PLAYERS +1` / `PLAYERS +8` joke, rendered exactly like a real granted
## modifier.
##
## [b]It reuses the tooltip-fan's own rows[/b] (`ui/tooltip_fan/panel_header.tscn`,
## `stat_value_row.tscn`, `slab_panel.tscn`) rather than authoring a lookalike,
## per #575. The one place they did not fit is the joke itself:
## [method ModSlabRow.bind] takes a [StatModifier] and resolves its tint through
## [StatRegistry], and #575 is explicit that [code]PLAYERS[/code] is not a real
## stat and must not be added there. So the joke goes through [StatValueRow],
## which asks only for a [StatDef]'s `display_name` and `tint_color` — and it is
## handed a transient one, built here and REGISTERED NOWHERE (see
## [method _menu_stat]). No board, no modifier, no registry entry: a string in
## the menu's own data, exactly as #575 asks.
##
## [b]What is shown is decided by the content, not by the topology.[/b] #575's
## acceptance asks for three things at once — a slab on SINGLE PLAYER, a
## description on each leaf, and nothing on a node with children — and the first
## and third contradict each other, since SINGLE PLAYER has two children. The
## reading that satisfies all three literal cases is the content one: a node
## gets a tooltip iff it carries a slab or a description, so SINGLE PLAYER and
## MULTIPLAYER get their joke and the ROOT (children, no content) gets nothing.
## The peek-ahead (#571) and this are then still mutually exclusive on the
## leaves, which is what the motion notes' "the preview is not a tooltip" is
## actually about.
##
## [b]The slab's text comes from the model[/b] ([member MenuGraph.Item.subtitle],
## authored as `"+1 PLAYERS"`), split here rather than restated — there must be
## one source for the joke, and it is the one the node itself is captioned from.
##
## Reveal is driven externally via [method set_progress] against the shared
## fixed-clock / progress(0..1) contract; this node owns no [Tween], like every
## other row it composes.

## The one-line descriptions, verbatim from #575. Menu-local copy, keyed by
## [MenuGraph]'s own ids — there is no description field on the model and this
## is the only consumer, so a table here beats widening [MenuGraph.Item].
const DESCRIPTIONS := {
	MenuGraph.ID_NEW_GAME: "Begin something new.",
	MenuGraph.ID_LOAD_GAME: "Return to a saved run.",
	MenuGraph.ID_LOCAL: "Same device, same screen.",
	MenuGraph.ID_HOST: "Open a game for others to join.",
	MenuGraph.ID_JOIN: "Enter a session by code.",
	MenuGraph.ID_OPTIONS: "Tune the experience.",
	MenuGraph.ID_EXIT: "Leave the tree.",
}

## Header over the joke slab. #575's words.
const SLAB_HEADER := "GRANTED ON SELECT"

const _ROW_SCENE := preload("res://ui/tooltip_fan/stat_value_row.tscn")

## Insets the body sits at inside the slab — must match the MarginContainer's
## authored constants, so [method _get_minimum_size] reports the true size.
const _H_INSET := 10.0
const _V_INSET := 8.0

## Scale the tooltip starts at when [method set_progress]'s `t` is 0.
@export_range(0.5, 1.0, 0.01) var start_scale: float = 0.92

## The item currently described, null for none.
var item: MenuGraph.Item = null

@onready var _slab: SlabPanel = %Slab
@onready var _header: PanelHeader = %Header
@onready var _description: Label = %Description
@onready var _rows: VBoxContainer = %Rows


func _ready() -> void:
	if item == null:
		visible = false


## Describes [param menu_item], or hides the tooltip when that item has nothing
## to say. Safe to call with null.
func bind(menu_item: MenuGraph.Item) -> void:
	item = menu_item
	_clear_rows()
	if not has_content(menu_item):
		item = null
		visible = false
		return
	visible = true
	var tint := tint_for(menu_item)
	_slab.tint_color = tint

	var slab := slab_for(menu_item)
	_header.bind(SLAB_HEADER if not slab.is_empty() else menu_item.title)

	var text := describe(menu_item.id)
	_description.text = text
	_description.visible = not text.is_empty()
	_description.add_theme_color_override(&"font_color", Emissive.at(tint, Emissive.LABEL))

	if not slab.is_empty():
		var row: StatValueRow = _ROW_SCENE.instantiate()
		_rows.add_child(row)
		row.bind_scalar(_menu_stat(slab[0] as String, tint), slab[1] as float)
	_rows.visible = _rows.get_child_count() > 0
	update_minimum_size()
	reset_size()


## Whether [param menu_item] has anything to show — a slab, a description, or
## neither. The whole of "what gets a tooltip"; see the class docs on why this
## is a content question rather than a leaf/non-leaf one.
static func has_content(menu_item: MenuGraph.Item) -> bool:
	if menu_item == null:
		return false
	return not slab_for(menu_item).is_empty() or not describe(menu_item.id).is_empty()


## The one-liner for a menu id, or `""`.
static func describe(id: StringName) -> String:
	return DESCRIPTIONS.get(id, "")


## The joke modifier as `[name, value]`, or `[]` for an item that carries none.
##
## [member MenuGraph.Item.subtitle] authors it the way it is CAPTIONED on the
## node — `"+1 PLAYERS"`, sign first — while a granted-modifier row reads the
## other way round, so the split happens here. A subtitle that is not a signed
## value followed by a name is not a modifier and yields no slab, rather than a
## row reading `+0 SOMETHING`.
static func slab_for(menu_item: MenuGraph.Item) -> Array:
	var empty: Array = []
	if menu_item == null:
		return empty
	var text := menu_item.subtitle.strip_edges()
	if text.is_empty():
		return empty
	var parts := text.split(" ", false, 1)
	if parts.size() < 2:
		return empty
	var value := parts[0].strip_edges()
	if not (value.begins_with("+") or value.begins_with("-")):
		return empty
	return [parts[1].strip_edges(), value.to_float()]


## The identity colour the tooltip is tinted by — the same archetype colour the
## node itself renders at, read through #569's map so there is no second one.
static func tint_for(menu_item: MenuGraph.Item) -> Color:
	if menu_item == null:
		return Color.WHITE
	var archetype := MenuNodeView.archetype_for(menu_item.archetype)
	return archetype.color if archetype != null else Color.WHITE


## Applies the reveal at clock position `t` (0..1): cubic ease-out driving scale
## and fade. Matches [method ModSlabRow.set_progress].
func set_progress(t: float) -> void:
	var eased := _ease_out(clampf(t, 0.0, 1.0))
	scale = Vector2.ONE * lerpf(start_scale, 1.0, eased)
	var m := modulate
	m.a = eased
	modulate = m


## A [StatDef] that exists only for the length of this tooltip.
##
## [b]It is never registered.[/b] #575: [i]"PLAYERS is not a real stat and must
## not be added to StatRegistry. It is a string in the menu's own data."[/i]
## [StatValueRow] reads exactly two fields off a def — the display name and the
## tint — so handing it a transient one reuses the shipped row without inventing
## a stat, and nothing downstream can ever look this up because nothing
## downstream has been told it exists.
static func _menu_stat(display_name: String, tint: Color) -> StatDef:
	var def := StatDef.new()
	def.display_name = display_name
	def.tint_color = tint
	return def


func _clear_rows() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()


## Content-driven, like [method ModSlabRow._get_minimum_size] — a long
## description wraps and grows the tooltip instead of overflowing it.
func _get_minimum_size() -> Vector2:
	var body: Control = get_node_or_null("%Body") as Control
	if body == null:
		return Vector2.ZERO
	return body.get_combined_minimum_size() + Vector2(_H_INSET * 2.0, _V_INSET * 2.0)


static func _ease_out(t: float) -> float:
	var inv := 1.0 - t
	return 1.0 - inv * inv * inv
