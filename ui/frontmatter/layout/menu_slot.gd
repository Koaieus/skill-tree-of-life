@tool
class_name MenuSlot
extends Control

## One authored seat in a [MenuFanHarness] — an invisible spacer that stands for
## exactly one [MenuGraph] item (#589 D2/D5), and carries everything about how
## that item LOOKS (#591).
##
## [b]A slot carries no pixels.[/b] It is a rectangle in a container, and the
## only thing [FrontmatterLayout] asks it for is where its centre landed once the
## container had its say, plus the [Look] it hands the view. The node that
## eventually draws there is a [MenuNodeView] living under `%GraphLayer` in WORLD
## space; this Control tree is screen space and is freed before anything animates
## (#589 D3) — which is why the look is COPIED out into a [Look] rather than read
## off a slot that no longer exists.
##
## [b]The row height IS the pitch knob.[/b] A [VBoxContainer] separates adjacent
## children by `separation`, so the distance between two slot CENTRES is
## `(height_a + height_b) * 0.5 + separation`. Giving one slot a taller box is
## how a fan buys room around a single option without loosening the whole fan —
## the defect #589 names, where the root fan applied the clearance `MULTIPLAYER`
## needed uniformly to `OPTIONS -> EXIT`, which needed none of it.
##
## [b]The split with [MenuGraph] is #589 D5.[/b] The tree keeps topology and
## routing — `parent`, `children`, `panel`, `route`, `disabled` — and every
## display string, tint and size lives here, in a scene an author can see at
## full-screen scale. Routing is the one non-visual part and
## `test/unit/ui/test_meta_routing_parity.gd` pins it against the live
## `meta_root.gd`, so it stays where that net can reach it.


## One node's look, copied off its slot so it outlives the harness.
##
## A plain record with no [Node] in it, for the same reason [MenuGraph.Item] is
## one: [method MenuFanHarness.measure] frees the whole Control tree before the
## menu is built, so anything a [MenuNodeView] or a [MenuTooltip] still needs
## has to have been lifted out of it first.
class Look extends RefCounted:
	## The [MenuGraph] id this describes, or a decorative slot's own name.
	var id: StringName = &""
	## The all-caps label on the node itself.
	var title: String = ""
	## The small slab under the title — the `+1 PLAYERS` / `+8 PLAYERS` joke
	## (#575). Empty for nodes that do not carry one.
	var subtitle: String = ""
	## An `archetypes/*.tres` id, used by #569 for the tint and the carve shape.
	## Menu-local: the archetype only supplies a LOOK here, no stats.
	var archetype: StringName = &""
	## The disk's world radius, in the units [member MenuNodeView.radius] takes.
	var radius: float = 32.0


## The [MenuGraph] id this seat stands for. Empty is a programming error:
## [method FrontmatterLayout.solve] cross-checks every slot against the tree, so
## an unnamed slot fails loudly at build rather than silently placing nothing.
##
## A [member decorative] slot names nothing in the tree, so its id is just a key
## — unique among slots, and deliberately NOT a menu id.
@export var menu_id: StringName = &""

## The all-caps caption the node renders.
@export var title: String = ""

## The joke slab, authored the way the node is CAPTIONED — `"+1 PLAYERS"`, sign
## first. [method MenuTooltip.slab_for] turns it around into a granted-modifier
## row; a subtitle that is not `<signed value> <name>` carries no slab at all.
@export var subtitle: String = ""

## Which `archetypes/*.tres` brands this node. [MenuNodeView.ARCHETYPES] is the
## whole of the vocabulary; an id outside it renders the composite's own
## untinted default.
@export var archetype: StringName = &""

## The disk's world radius. Authored per node so the root can read bigger than
## its options (#593) without a `if id == ROOT` branch anywhere in code; the
## default is `node_visuals_composite.tscn`'s own 32.
@export_range(4.0, 128.0, 0.5) var radius: float = 32.0

## This seat is scenery, not a menu item — the owner's [i]"some should get
## pre-authored bonus nodes ... baked in a scene rather than programmatic
## exceptions of one giant `build()`"[/i] (#589 / #591).
##
## It still reserves its row, so it shapes the fan's pitch like any other slot,
## but the 1:1 cross-check skips it instead of asserting that [MenuGraph] knows
## its id — and asserts the opposite, that it does not.
@export var decorative: bool = false


## This slot's look, lifted out of the [Node] so it survives being freed.
func look() -> Look:
	var out := Look.new()
	out.id = menu_id
	out.title = title
	out.subtitle = subtitle
	out.archetype = archetype
	out.radius = radius
	return out
