@tool
class_name MenuNodeView
extends Node2D

## One node of the frontmatter menu tree, drawn with the REAL SkillNode
## visuals (#569).
##
## [b]It steals a scene, not a class.[/b] `node_visuals_composite.tscn` is a
## standalone [Node2D] that is [i]fed by[/i] [SkillNode] and never reaches up —
## no `get_parent()`, no [Graph], no [Entity], no [StatBoard] — so the menu
## instances it directly and pushes the same exports [SkillNode] would.
## `skill_node.tscn` itself is NOT instanced: it works standalone, but it is
## gameplay behaviour this menu has no use for. `test_menu_node_view.gd` walks
## the built tree and asserts none of those classes is anywhere in it.
##
## The mouse is a [MenuNodePickRegion] child — see that file for why the hit
## area is a [Control] rather than an [Area2D] (#583).
##
## The general rule this is an instance of (#567, restated by the owner on
## #569): [i]"the visuals are reusable" is a claim about a scene or a shader,
## not about the class that drives it.[/i] The composite passes that test;
## `graph/edge.tscn` does not, which is why [MenuEdgeView] rebuilds the edge
## over the shader instead.
##
## [b]Identity comes from an [Archetype], and its colour is COMPUTED[/b] —
## `Archetype.color` reads through to `StatRegistry.get_def(primary_stat).tint_color`
## and is never authored on the resource. The design canvas's own `hue` field
## is deliberately not ported: two of its hues disagree with the repo, and the
## repo wins (OPTIONS is perception-purple, EXIT is constitution-white).

## Archetype id -> the archetype resource that brands it. The map lives here, on
## the view, because the id is authored data ([member MenuSlot.archetype]) and
## turning it into a tint is this unit's job. `preload`ed rather than resolved by string path,
## so a typo'd id fails to load rather than rendering an untinted node.
const ARCHETYPES := {
	&"strength": preload("res://archetypes/strength.tres"),
	&"dexterity": preload("res://archetypes/dexterity.tres"),
	&"intelligence": preload("res://archetypes/intelligence.tres"),
	&"wisdom": preload("res://archetypes/wisdom.tres"),
	&"perception": preload("res://archetypes/perception.tres"),
	&"constitution": preload("res://archetypes/constitution.tres"),
}

## `node_visuals_composite.tscn` authors `geom_inner_r = 24` against
## `geom_outer_r = 32`. [member radius] scales both by that ratio so the disk
## edge and the rim floor keep their proportions at any size, instead of a
## bigger node growing a rim that still ends where a 32px one did.
const _INNER_RADIUS_RATIO := 24.0 / 32.0

## Gap between the rim and the caption's box, in world units.
const _LABEL_GAP := 10.0

## The caption's box in WORLD units — what it occupies once supersampled and
## scaled back down. Matches the box `menu_node_view.tscn` authors.
const _CAPTION_BOX := Vector2(220.0, 24.0)

## The caption is rasterized this many times larger than it is drawn.
##
## [b]Because this menu draws text at every scale there is.[/b] A [Label] rasters
## its glyphs at `font_size` and the canvas then stretches that bitmap: the
## collapsed peek nodes sit at [constant FrontmatterLayout.PREVIEW_SCALE] (0.42),
## every fan is navigated at [constant FrontmatterLayout.TREE_ZOOM] (1.0 since
## #603 collapsed the per-fan zoom; the root menu's own 1.35 is gone), and #574's
## splash parks at [constant FrontmatterLayout.SPLASH_ZOOM]. Every one of those
## is a resample of a 16px raster, and it read as the aliased, mushy caption the
## owner called out on 2026-08-26.
##
## Rastering at 3x and drawing at 1/3 puts the raster ABOVE every scale the menu
## uses, so magnifying is a downsample and never an upsample. Minifying is then
## covered by the font's mipmaps, which is why the scene authors
## `texture_filter = 4` (LINEAR_WITH_MIPMAPS) on the caption — Godot's default
## canvas filter has no mipmap stage, so the mipmaps the import generates would
## otherwise never be sampled and the peek captions would break into fragments.
##
## [b]Scoped to this Label rather than done in the font import.[/b] `oversampling`
## in `Cinzel-VariableFont_wght.ttf.import` is the same trick globally, and it
## measurably THINS the HUD's own `CinzelHeader` labels, which are screen-space at
## zoom 1 and want a native raster. `generate_mipmaps` is safe to set globally
## precisely because it is inert until a CanvasItem asks for a mipmap filter.
##
## [b]Applied on the node, in `menu_node_view.tscn` (#612), not here.[/b] `%Title`
## authors `scale = (0.333333, 0.333333)`, a `font_size` override of 48 and
## `size = (660, 72)` directly — all three are static, none vary per node, so
## the scene is where they belong. This constant documents WHY those three
## numbers are what they are (`16 * 3 = 48`, `_CAPTION_BOX * 3 = (660, 72)`,
## `1 / 3`); nothing at runtime reads it any more.
const _CAPTION_SUPERSAMPLE := 3.0

## The label the composite is captioned with.
@export var title: String = "":
	set(value):
		title = value
		_sync_label()

## Brands the node: the rim tint, the entity tint and the carve glyph all come
## from here. Null renders the composite's own authored defaults.
@export var archetype: Archetype = null:
	set(value):
		archetype = value
		_sync_identity()
		_sync_label()

## "This node is on the current focus path" (#569). Unallocated siblings render
## unallocated — the composite reads it as `allocation_level`, which is its own
## sole source of truth for the inherited `allocated` flag.
@export var allocated: bool = false:
	set(value):
		allocated = value
		_sync_identity()
		_sync_label()

## Node size in world units. [b]Pushed through [method SkillNodeVisual.configure][/b] —
## assigning `radius` on the composite only calls `queue_redraw()` and does NOT
## reach its children, so a plain assignment silently changes nothing.
@export_range(4.0, 128.0, 0.5) var radius: float = 32.0:
	set(value):
		radius = value
		_sync_radius()

## The mouse found this node, or left it. Raised by the [MenuNodePickRegion]
## child and re-emitted here so a caller binds to the VIEW and never has to know
## the hit area exists (#583).
signal hover_entered
signal hover_exited

## A left click landed on the disk. #570 answers it exactly as #576's
## `ui_accept` is answered, through the same [method FrontmatterRoot.focus].
signal activated

@onready var _visuals: Node2D = %Visuals
@onready var _label: Label = %Title
@onready var _pick: MenuNodePickRegion = %PickRegion


func _ready() -> void:
	_sync_identity()
	_sync_radius()
	_sync_label()
	_pick.mouse_entered.connect(hover_entered.emit)
	_pick.mouse_exited.connect(hover_exited.emit)
	_pick.activated.connect(activated.emit)


## Everything the fan scene authors about one node, in one call — what #570 uses
## when it builds the tree, so no caller has to remember which export means what.
##
## Takes the [MenuSlot.Look] rather than the [MenuGraph.Item] since #591: the
## tree carries no display string, and the radius has no other source. A null
## look leaves the view at the composite's own defaults rather than crashing —
## an id nothing authors is caught by [method FrontmatterLayout.solve]'s
## cross-check, which is a better place to hear about it than here.
func bind(look: MenuSlot.Look, is_allocated: bool = false) -> void:
	allocated = is_allocated
	if look == null:
		return
	# radius FIRST: `title=` and `archetype=` both sync the caption, which reads
	# `radius` to park itself under the rim (#612) — setting radius last would
	# leave the caption parked at the PREVIOUS radius until the next sync.
	radius = look.radius
	title = look.title
	archetype = archetype_for(look.archetype)


## The archetype resource for a [member MenuSlot.archetype] id, or null for an
## id nothing brands.
static func archetype_for(id: StringName) -> Archetype:
	return ARCHETYPES.get(id) as Archetype


## The colour this view renders at — the archetype's computed tint, or the
## composite's neutral default when nothing brands it. Read by [MenuEdgeView]
## so an edge's two ends take their nodes' colours.
func display_color() -> Color:
	if archetype == null:
		return _visuals.archetype_tint if _visuals != null else Color.WHITE
	return archetype.color


func _sync_identity() -> void:
	if not is_node_ready():
		return
	_visuals.allocation_level = 1 if allocated else 0
	if archetype == null:
		return
	var tint := archetype.color
	# The menu has no entities, so "this is MINE" and "this is what I AM"
	# collapse onto one colour — the same thing `node_visuals_panel.tscn` does
	# when it previews a composite with no [SkillNode] over it.
	_visuals.archetype_tint = tint
	_visuals.entity_tint = tint
	_visuals.carve_shape = archetype.carve_shape


func _sync_radius() -> void:
	if not is_node_ready():
		return
	_visuals.configure(radius)
	_visuals.geom_outer_r = radius
	_visuals.geom_inner_r = radius * _INNER_RADIUS_RATIO
	# The hit area is the disk, so it is sized from the same number rather than
	# authored alongside it — a rim that grew past its pick region would be
	# clickable only in the middle.
	_pick.radius = radius


## Caption: Cinzel from the project theme's `CinzelHeader` variation, tinted by
## the archetype and lifted by allocation. The lift is a named [Emissive] tier,
## never a hand-picked float (`.claude/rules/hdr-color.md`) — [constant
## Emissive.VALUE] is "this is lit", [constant Emissive.INERT] sits exactly at
## the bloom threshold and never blooms.
func _sync_label() -> void:
	if not is_node_ready():
		return
	_label.text = title
	_supersample_caption()
	var base := display_color()
	_label.add_theme_color_override(
		&"font_color", Emissive.at(base, Emissive.VALUE if allocated else Emissive.INERT)
	)


## Parks the caption OVER the rim. The scale, font size and raster box that
## make this a [constant _CAPTION_SUPERSAMPLE]x supersample are authored on
## `%Title` in `menu_node_view.tscn` (#612) — none of them vary per node. Only
## the position does: it reads [member radius], which arrives at runtime via
## [method bind].
##
## [b]Above, not below, by owner call 2026-09-03 (#734).[/b] Verbatim:
## [i]"move the captions of these skillnodes to be above the nodes instead.
## doesn't matter if they get occluded by vfx for a split second, given ppl know
## what they are clicking."[/i] It reads as cosmetic and is not: the allocation
## needle rises NORTH out of the node, so the node has to sit LOW on screen for
## the needle to fit — and while the caption hung BELOW, pushing the node down
## ran the caption off the bottom of the screen. Moving it above is what lifts
## that constraint, and it is what lets [constant FrontmatterLayout.CHARGE_SLOT_Y_RATIO]
## push the BOOM's slot south far enough to afford a much closer zoom.
##
## [b]A [Control]'s `scale` pivots on its own top-left, which is its
## `position`.[/b] So the box is laid out in RASTER units and its top-left is
## placed where the SCALED box's top-left belongs — which is why going above
## subtracts the box's own HEIGHT as well as the gap, rather than just negating
## the offset. Get that wrong and every caption in the menu sits one box-height
## off. Centring by `-_CAPTION_BOX.x * 0.5` rather than by the raster width is
## the same correction on the other axis.
func _supersample_caption() -> void:
	_label.position = Vector2(
		-_CAPTION_BOX.x * 0.5, -(radius + _LABEL_GAP) - _CAPTION_BOX.y
	)


## Plays the game's own allocation spike over this node — the "skill point from
## the heavens" needle [AllocationVFX] drops on every real allocation.
##
## [b]Reused as a static function, not by mounting an [AllocationVFX].[/b] That
## node binds to an [AllocationSystem] and a [BattleSystem] and connects to
## [Events], none of which exist here; the spike itself needs a position, two
## radii and a colour, which is exactly what
## [method AllocationVFX.spawn_alloc_spike] now takes. Same rule as the
## composite this view is drawn with — [i]reusable means a scene or a function,
## never the class that drives it.[/i]
##
## Parented to THIS view, so a spike over a collapsed node is scaled down with
## it. The effect sets its own absolute z and so still draws over the disk.
func play_allocation_spike() -> void:
	AllocationVFX.spawn_alloc_spike(
		self, global_position, radius * _INNER_RADIUS_RATIO, radius, display_color()
	)


## Plays the game's own dealloc lift over this node's spot — the puff that
## marks a node's spot as it loses focus-path allocation and collapses back
## onto its parent.
##
## [b]Reused as a static function, not by mounting an [AllocationVFX][/b] —
## same reason as [method play_allocation_spike].
##
## [b]Parented to [param host] (the shell's `%GraphLayer`), NOT to this
## view[/b] — unlike the spike. The node being left is about to collapse to
## `FrontmatterLayout.PREVIEW_SCALE` on its own parent; a puff parented to it
## would shrink away with it instead of marking the spot it vacated. See the
## frontmatter VFX acceptance spec (#599).
func play_dealloc_lift(host: Node2D) -> void:
	AllocationVFX.spawn_dealloc_lift(
			host, global_position, radius * _INNER_RADIUS_RATIO, display_color()
	)
