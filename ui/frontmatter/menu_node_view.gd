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
## a fan is navigated at its authored zoom (1.35 on the root menu), and #574's
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
	title = look.title
	archetype = archetype_for(look.archetype)
	radius = look.radius


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


## Parks the caption under the rim, at [constant _CAPTION_SUPERSAMPLE] times its
## drawn size — see that constant for why.
##
## A [Control]'s `scale` pivots on its own top-left, which is its `position`, so
## the box has to be laid out in RASTER units and left-aligned to where the
## scaled box's left edge belongs. Centring by `-_CAPTION_BOX.x * 0.5` rather
## than by the raster width is the whole of that correction.
func _supersample_caption() -> void:
	_label.scale = Vector2.ONE / _CAPTION_SUPERSAMPLE
	_label.add_theme_font_size_override(
		&"font_size", int(round(_base_font_size() * _CAPTION_SUPERSAMPLE))
	)
	_label.size = _CAPTION_BOX * _CAPTION_SUPERSAMPLE
	_label.position = Vector2(-_CAPTION_BOX.x * 0.5, radius + _LABEL_GAP)


## The theme's own `CinzelHeader` size, cached before the first override hides
## it — `get_theme_font_size` answers with the override once one exists, so
## reading it every sync would compound 16 -> 48 -> 144.
func _base_font_size() -> int:
	if _cached_font_size < 0:
		_cached_font_size = _label.get_theme_font_size(&"font_size")
	return _cached_font_size


var _cached_font_size: int = -1


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
