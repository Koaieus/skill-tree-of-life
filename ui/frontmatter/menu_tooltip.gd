@tool
class_name MenuTooltip
extends VBoxContainer

## The slab stack a menu node shows when you point at it (#567 / #575 / #588) —
## a centred column of [SlabRow]s sitting directly under the node: its title (or
## `GRANTED ON SELECT`), a one-line description for most of them, and for SINGLE
## PLAYER / MULTIPLAYER the `PLAYERS +1` / `PLAYERS +8` joke, rendered exactly
## like a real granted modifier.
##
## [b]It is a stack of rows, not a panel with a body.[/b] #588 replaced the
## previous `Slab` + `Margin` + `Body` + autowrap `Description` structure, which
## carried a genuine layout cycle — the tooltip's minimum read `%Body`'s combined
## minimum, `%Body` was anchored to the tooltip, and an autowrap [Label] inside
## it derived its height from that width. It settled at ~470px for two lines of
## text. The stack deletes the cycle rather than converging it: every row is a
## child of a real [Container] (so it DOES shrink when its minimum drops), the
## stack authors its own [member Control.custom_minimum_size].x, and no row
## derives a width from the stack's size. This is [AddonItem]'s shape verbatim,
## which has never shown the bug.
##
## [b]It reuses the tooltip-fan's own row[/b] rather than authoring a lookalike,
## per #575 — [SlabRow] is the base #588 extracted out of [ModSlabRow] for
## exactly this: the same slab, taking any text and any tint, with no
## [StatModifier] and no [StatRegistry] behind it. The joke therefore needs no
## transient [StatDef] any more (the old `_menu_stat()` existed only to feed
## [StatValueRow] two fields); `PLAYERS` is a string in the menu's own data and
## reaches nothing, exactly as #575 asks.
##
## [b]What is shown is decided by the content, not by the topology.[/b] #575's
## acceptance asks for three things at once — a slab on SINGLE PLAYER, a
## description on each leaf, and nothing on a node with children — and the first
## and third contradict each other, since SINGLE PLAYER has two children. The
## reading that satisfies all three literal cases is the content one: a node
## gets a tooltip iff it carries a slab or a description, so SINGLE PLAYER and
## MULTIPLAYER get their joke and the ROOT (children, no content) gets nothing.
##
## [b]The slab's text comes from the authored slot[/b] ([member
## MenuSlot.subtitle], authored as `"+1 PLAYERS"` in `root_menu.tscn`), split
## here rather than restated — there must be one source for the joke, and it is
## the one the node itself is captioned from. #591 moved it off [MenuGraph],
## which now carries topology and routing only.
##
## [b]It fades, it never hides.[/b] Nothing here ever writes `visible = false`:
## a hidden [Control] skips layout, which is what breaks size convergence in the
## first place. "Nothing to say" rests at `modulate.a = 0` via
## [method set_progress], the same contract [SlabRow] itself follows.
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

const _ROW_SCENE := preload("res://ui/tooltip_fan/slab_row.tscn")

## How much of the title/description row's tint is pushed toward white — the
## header reads as the loudest line, the description as the quietest.
const _HEADER_TINT_MIX := 0.55
const _BODY_TINT_MIX := 0.3

## Scale the tooltip starts at when [method set_progress]'s `t` is 0.
@export_range(0.5, 1.0, 0.01) var start_scale: float = 0.92

## The look currently described, null for none.
var look: MenuSlot.Look = null


func _ready() -> void:
	# Centre the scale pivot so a partially revealed stack still reads as
	# centred under its node — [FrontmatterRoot] places by `position.x +
	# size.x * 0.5`, which is only the VISUAL centre if the shrink is about
	# the middle rather than the top-left corner.
	resized.connect(_recentre_pivot)
	_recentre_pivot()
	if Engine.is_editor_hint():
		return
	set_progress(0.0)


## Describes [param menu_look], or empties the tooltip when that node has
## nothing to say. Safe to call with null.
func bind(menu_look: MenuSlot.Look) -> void:
	look = menu_look
	_clear_rows()
	if not has_content(menu_look):
		look = null
		set_progress(0.0)
		_fit()
		return
	var tint := tint_for(menu_look)
	var slab := slab_text(menu_look)

	_add_row(SLAB_HEADER if not slab.is_empty() else menu_look.title, tint, _HEADER_TINT_MIX)
	if not slab.is_empty():
		_add_row(slab, tint, _BODY_TINT_MIX)
	var text := describe(menu_look.id)
	if not text.is_empty():
		_add_row(text, tint, _BODY_TINT_MIX)
	_fit()


## Whether [param look] has anything to show — a slab, a description, or
## neither. The whole of "what gets a tooltip"; see the class docs on why this
## is a content question rather than a leaf/non-leaf one.
static func has_content(look: MenuSlot.Look) -> bool:
	if look == null:
		return false
	return not slab_for(look).is_empty() or not describe(look.id).is_empty()


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
static func slab_for(look: MenuSlot.Look) -> Array:
	var empty: Array = []
	if look == null:
		return empty
	var text := look.subtitle.strip_edges()
	if text.is_empty():
		return empty
	var parts := text.split(" ", false, 1)
	if parts.size() < 2:
		return empty
	var value := parts[0].strip_edges()
	if not (value.begins_with("+") or value.begins_with("-")):
		return empty
	return [parts[1].strip_edges(), value.to_float()]


## The joke rendered the way a granted-modifier row reads it — `"PLAYERS +1"`,
## name first — or `""` for an item that carries no slab.
static func slab_text(look: MenuSlot.Look) -> String:
	var slab := slab_for(look)
	if slab.is_empty():
		return ""
	return "%s %s" % [slab[0] as String, _format_value(slab[1] as float)]


## The identity colour the tooltip is tinted by — the same archetype colour the
## node itself renders at, read through #569's map so there is no second one.
static func tint_for(look: MenuSlot.Look) -> Color:
	if look == null:
		return Color.WHITE
	var archetype := MenuNodeView.archetype_for(look.archetype)
	return archetype.color if archetype != null else Color.WHITE


## Applies the reveal at clock position `t` (0..1): cubic ease-out driving scale
## and fade. Matches [method SlabRow.set_progress].
func set_progress(t: float) -> void:
	var eased := _ease_out(clampf(t, 0.0, 1.0))
	scale = Vector2.ONE * lerpf(start_scale, 1.0, eased)
	var m := modulate
	m.a = eased
	modulate = m


## Mints one row. Rows are driven to full reveal immediately — the STACK's own
## [method set_progress] owns the fade, so a row that also sat at `t = 0` would
## never appear.
func _add_row(text: String, tint: Color, tint_mix: float) -> void:
	var row: SlabRow = _ROW_SCENE.instantiate()
	add_child(row)
	row.text_tint_mix = tint_mix
	row.bind_text(text, tint)
	row.set_progress(1.0)


func _clear_rows() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


## Shrinks the stack back onto its rows.
##
## The stack is free-floating (it lives in [FrontmatterRoot]'s `CanvasLayer`,
## not inside a parent Container), and a Control outside a Container never
## shrinks on its own when its minimum drops. `size = (authored width, 0)`
## clamps UP against the combined minimum, so this is one call and no
## convergence loop — nothing in a row's minimum depends on the stack's size.
func _fit() -> void:
	size = Vector2(custom_minimum_size.x, 0.0)
	_recentre_pivot()


func _recentre_pivot() -> void:
	pivot_offset = size * 0.5


## `+1` / `-3`, or one decimal for a value that is not whole.
static func _format_value(value: float) -> String:
	var whole := roundi(value)
	if is_equal_approx(value, float(whole)):
		return "%+d" % whole
	return "%+.1f" % value


static func _ease_out(t: float) -> float:
	var inv := 1.0 - t
	return 1.0 - inv * inv * inv
