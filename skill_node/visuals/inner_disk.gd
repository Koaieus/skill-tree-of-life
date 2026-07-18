@tool
extends SkillNodeVisual
## Inner disk: semi-sphere `canvas_item` shader (#123). Filled circle with an
## offset radial highlight, lit in the entity's color when allocated and in a
## dark neutral when not — the dome, its shine and its weld dent draw either
## way, so allocation is a color change, not a topology change. See
## inner_disk.gdshader for the fragment logic.
##
## ONE shared ShaderMaterial across every inner_disk instance (built lazily,
## cached in the static [member _shared_material]) — per-node values ride as
## the shader's `instance uniform`s via
## [method CanvasItem.set_instance_shader_parameter], so many disks on
## screen still batch into a single draw call instead of costing one
## draw call each (which a per-node `resource_local_to_scene` duplicate
## material would). See docs/domain/skill-node-visuals-shaders.md.
##
## Composes the weld glyph directly as a height-field dent in its own shader
## (see inner_disk.gdshader's carve_kind/weld_* uniforms and
## lighting.gdshaderinc's sn_polygon_facet/sn_bowl_drop) rather than as a
## separate WeldSymbol node — the glyph used to be a sibling Node2D with its
## own CPU twin of this shading formula; folding it into this same fragment
## shader means it can't drift from the disk's own lighting, by
## construction. See .claude/rules/skill-node-visuals.md.

const EmblemSpec = preload("res://skill_node/visuals/emblem/emblem_spec.gd")
const SHADER := preload("res://skill_node/visuals/inner_disk.gdshader")

## Which CARVE shape family the disk etches — the single selector replacing
## the old show_weld/show_diamond mutually-exclusive bool pair (see
## .claude/rules/skill-node-visuals.md and [method set_carve]).
enum CarveKind { NONE, POLYGON, GEM }

static var _shared_material: ShaderMaterial

## Loot relic gem cut (#168), viewed from the SIDE — flat table facet at top,
## tapering shoulders down to the widest girdle, then a pavilion tapering to a
## single point at the bottom (not the top-down radially-symmetric crown this
## used to bake). Baked ONCE into a small shared LUT (see _build_gem_lut)
## rather than recomputed per-pixel per-instance like the weld glyph — every
## relic wants the exact same cut, so there's nothing to gain from re-deriving
## it analytically on every node, every frame. Geometry constants here MUST
## mirror lighting.gdshaderinc's SN_GEM_DEPTH_SCALE / SN_GEM_GRAD_SCALE (the
## bake and the decode are two halves of one encoding).
const GEM_LUT_SIZE := 128
const GEM_TOP_Y := 0.55
const GEM_GIRDLE_Y := -0.05
const GEM_POINT_Y := -0.85
const GEM_TOP_HALF_WIDTH := 0.32
const GEM_GIRDLE_HALF_WIDTH := 0.78
## Fraction of the interior→boundary ramp that stays flat (the table facet).
const GEM_TABLE_T := 0.15
const GEM_DEPTH := 0.35
const GEM_GRAD_SCALE := 3.0
## The side-view silhouette: flat top edge (the table), tapering shoulders out
## to the girdle (widest point), then a pavilion tapering to a single point.
const GEM_VERTICES := [
	Vector2(GEM_TOP_HALF_WIDTH, GEM_TOP_Y),
	Vector2(-GEM_TOP_HALF_WIDTH, GEM_TOP_Y),
	Vector2(-GEM_GIRDLE_HALF_WIDTH, GEM_GIRDLE_Y),
	Vector2(0.0, GEM_POINT_Y),
	Vector2(GEM_GIRDLE_HALF_WIDTH, GEM_GIRDLE_Y),
]
static var _gem_lut: ImageTexture

## Saturation of the disk tint (0 = grey, 1 = fully saturated) — the private
## mix against which [member SkillNodeVisual.entity_tint] is blended, the
## disk's counterpart to RimRing's bronze metal.
@export_range(0.0, 1.0, 0.01) var tint_mix: float = 0.6:
	set(value):
		tint_mix = value
		_sync_material()

## Disk radius. Defaults to SkillNode.inner_radius (24) — see
## .claude/rules/skill-node-visuals.md.
@export_range(1.0, 128.0, 0.5) var disk_radius: float = 24.0:
	set(value):
		disk_radius = value
		queue_redraw()

## Offset of the specular highlight in the disk's normalized (-1..1) local
## space. Fixed for now; the shader/uniform split lets this be driven by
## mouse position or a light source later without touching fragment logic.
@export var highlight_position: Vector2 = Vector2(-0.35, -0.35):
	set(value):
		highlight_position = value
		_sync_material()

@export_range(0.0, 1.0, 0.01) var highlight_intensity: float = 0.85:
	set(value):
		highlight_intensity = value
		_sync_material()

## Which shape family the dome carves — NONE by default per the locked design
## ("showWeld — off is the new default; empty center. on restores the
## archetype shape" — Rim Forge Lab): the disk's own semi-sphere shading +
## specular highlight is the baseline read, a carve is an opt-in accent. This
## replaces the old show_weld/show_diamond mutually-exclusive bool pair with
## one selector — see .claude/rules/skill-node-visuals.md and [method set_carve].
@export var carve_kind: CarveKind = CarveKind.NONE:
	set(value):
		carve_kind = value
		_sync_material()

## Regular-polygon side count for the POLYGON carve. STANDALONE PREVIEW ONLY —
## once [method set_carve] receives an archetype carve it overwrites this from
## the resolved [EmblemSpec.polygon_sides] (see [ArchetypeShape], the canonical
## archetype -> sides mapping; this file no longer keeps its own copy). Exists
## so the disk still previews a shape in the sandbox / node_visuals_panel.tscn
## before a carve has been injected — same "local export as offline fallback"
## precedent as [member lighting] below.
@export_range(3, 16, 1) var weld_sides: int = 3:
	set(value):
		weld_sides = value
		_sync_material()

## Anisotropic X-squish for the POLYGON carve (see [PolygonCarveShape]) — 1.0
## is regular, < 1.0 narrows the shape (DEX's "diamond squished from the
## sides"). STANDALONE PREVIEW default; [method set_carve] overwrites it from
## [member EmblemSpec.polygon_squish].
@export_range(0.3, 1.0, 0.01) var weld_squish: float = 1.0:
	set(value):
		weld_squish = value
		_sync_material()

## Glyph circumradius relative to the disk radius. At 1.0 the glyph's
## vertices sit exactly on the disk's circle.
@export_range(0.4, 1.15, 0.01) var weld_k: float = 0.75:
	set(value):
		weld_k = value
		_sync_material()

## Max depth of the glyph's bowl dent at its own visual center — see
## inner_disk.gdshader/lighting.gdshaderinc's sn_bowl_drop.
@export_range(0.0, 1.0, 0.01) var well_depth: float = 0.35:
	set(value):
		well_depth = value
		_sync_material()

## Shared light source (see [LightingStyle]), INJECTED AT RUNTIME by the
## composite — a plain `var`, deliberately NOT `@export`: it holds a
## composite-built resource, and an exported field assigned in a @tool context
## gets baked into the scene by an editor save (the gotcha in
## .claude/rules/skill-node-visuals.md). When null (standalone preview) the
## local highlight_* @exports are edited directly.
var lighting: LightingStyle = null:
	set(value):
		if lighting != null and lighting.changed.is_connected(_apply_lighting):
			lighting.changed.disconnect(_apply_lighting)
		lighting = value
		if lighting != null and not lighting.changed.is_connected(_apply_lighting):
			lighting.changed.connect(_apply_lighting)
		_apply_lighting()


func _apply_lighting() -> void:
	if lighting == null:
		return
	highlight_position = lighting.highlight_position
	highlight_intensity = lighting.highlight_intensity


## The disk is the node's ownership read, so it draws in the entity's color.
func _on_identity_changed() -> void:
	_sync_material()


func _ready() -> void:
	if _shared_material == null:
		_shared_material = ShaderMaterial.new()
		_shared_material.shader = SHADER
	if _gem_lut == null:
		_gem_lut = _build_gem_lut()
	# Plain (non-instance) uniform — the LUT is identical for every InnerDisk,
	# so it's set ONCE on the shared material rather than per-instance. (This is
	# on the SHARED material, so it does NOT claim a per-instance buffer slot —
	# binding `material` on THIS CanvasItem is what does, hence the gate below.)
	_shared_material.set_shader_parameter(&"gem_lut", _gem_lut)
	# Re-sync when the disk is shown after being hidden — see the visibility gate
	# in _sync_material (#172). Fires on this node too when an ancestor (a fogged
	# SkillNode, the invisible Node Graph preview graph) toggles visibility.
	visibility_changed.connect(_sync_material)
	_sync_material()


func configure(new_radius: float) -> void:
	super.configure(new_radius)
	disk_radius = new_radius


func _sync_material() -> void:
	if not is_node_ready():
		return
	# Each set_instance_shader_parameter below claims a slot in the shared global
	# instance-uniform buffer — even on a CanvasItem that never renders (#172).
	# A disk on a fog-hidden SkillNode, or on the procgen Node Graph preview's
	# invisible graph, has no reason to hold one; gate on tree visibility and let
	# the visibility_changed re-sync above set the uniforms the frame it shows.
	if not is_visible_in_tree():
		return
	# Bind the shared material HERE (not in _ready): the bind is itself what
	# allocates this instance's uniform-buffer slot, so a hidden/fogged disk that
	# never reaches this line never claims one. Guard the reassign so we don't
	# churn `material` (a property the inspector watches) on every resync.
	if material != _shared_material:
		material = _shared_material
	set_instance_shader_parameter(&"tint_color", entity_tint)
	set_instance_shader_parameter(&"tint_mix", tint_mix)
	set_instance_shader_parameter(&"allocated", allocated)
	set_instance_shader_parameter(&"highlight_position", highlight_position)
	set_instance_shader_parameter(&"highlight_intensity", highlight_intensity)
	set_instance_shader_parameter(&"carve_kind", carve_kind)
	set_instance_shader_parameter(&"weld_sides", float(weld_sides))
	set_instance_shader_parameter(&"weld_squish", weld_squish)
	set_instance_shader_parameter(&"weld_k", weld_k)
	set_instance_shader_parameter(&"well_depth", well_depth)
	queue_redraw()


## Consumes a resolved central-emblem CARVE (docs/domain/skillnode-emblem.md) —
## the sanctioned entry point once a caller has an [EmblemResolver.Resolution],
## replacing hand-toggling [member show_weld]/[member show_diamond] separately
## (retired — see .claude/rules/skill-node-visuals.md). `carve` is the winning
## [EmblemSpec] (an [EmblemResolver] Resolution's `.carve`), or null for an
## empty dome. Switches on [member EmblemSpec.carve_style], not `source_kind` —
## `source_kind` stays purely descriptive (tie-break debugging, tooltip copy).
##
## - POLYGON (the archetype fallback, or any future analytic polygon source) ->
##   the weld height-field bowl, sized/squished to the carve's own
##   `polygon_sides`/`polygon_squish` (no per-instance re-derivation — the
##   winning spec already carries the numbers its [CarveShape] assigned it).
## - GEM (the loot relic's cut, #168) -> the gem LUT dent.
## - TEXTURE (keystone / spell / arbitrary bitmap art) -> no carve renderer
##   exists yet; the bake substrate for that art is deferred (see #245/#246),
##   so an empty dome is the honest fallback rather than misrepresenting the
##   node as its archetype shape when a higher-priority carve actually won.
func set_carve(carve: Variant) -> void:
	if carve == null:
		carve_kind = CarveKind.NONE
		return
	match carve.carve_style:
		EmblemSpec.CarveStyle.POLYGON:
			carve_kind = CarveKind.POLYGON
			weld_sides = carve.polygon_sides
			weld_squish = carve.polygon_squish
		EmblemSpec.CarveStyle.GEM:
			carve_kind = CarveKind.GEM
		_:
			carve_kind = CarveKind.NONE


func _draw() -> void:
	draw_rect(Rect2(Vector2(-disk_radius, -disk_radius), Vector2.ONE * disk_radius * 2.0), Color.WHITE)


## Bakes the gem cut's height field into a small shared LUT texture — built
## ONCE (lazily, cached in [member _gem_lut]) rather than recomputed per-pixel
## in the shader, since the shape is fixed and identical across every relic.
## This GDScript geometry IS the source of truth (the shader only decodes it
## via sn_gem_bump), not a parallel re-derivation of a GPU formula — see the
## class doc above and lighting.gdshaderinc.
##
## Encoding (must match sn_gem_bump's decode): R = drop/GEM_DEPTH, GB =
## grad/GEM_GRAD_SCALE remapped -1..1 -> 0..1, A = 1 inside the gem's outline
## else 0.
##
## Baked WITH mipmaps: the LUT (128px) is higher-resolution than the disk's
## on-screen footprint (~48-64px), so sampling it is a MINIFICATION, not a
## magnification — without mips, bilinear only blends 4 texels per screen
## pixel instead of properly box-filtering the ~2-3 texel neighborhood each
## screen pixel actually covers, aliasing exactly at the facet creases this
## LUT exists to render crisply. `filter_linear_mipmap` on the shader
## uniform (inner_disk.gdshader) is the other half of this fix.
static func _build_gem_lut() -> ImageTexture:
	var img := Image.create(GEM_LUT_SIZE, GEM_LUT_SIZE, false, Image.FORMAT_RGBA8)
	for y in GEM_LUT_SIZE:
		for x in GEM_LUT_SIZE:
			var u := (float(x) + 0.5) / float(GEM_LUT_SIZE)
			var v := (float(y) + 0.5) / float(GEM_LUT_SIZE)
			var p := (Vector2(u, v) - Vector2(0.5, 0.5)) * 2.0
			var hg := _gem_height_grad(p)
			var r := hg.x / GEM_DEPTH
			var g := clampf(hg.y / GEM_GRAD_SCALE * 0.5 + 0.5, 0.0, 1.0)
			var b := clampf(hg.z / GEM_GRAD_SCALE * 0.5 + 0.5, 0.0, 1.0)
			var a := 1.0 if hg.x > 0.0 or _gem_inside(p) else 0.0
			img.set_pixel(x, y, Color(r, g, b, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Centroid of [constant GEM_VERTICES] — the pentagon's "deepest point" for
## the table+ramp height convention below.
static func _gem_centroid() -> Vector2:
	var c := Vector2.ZERO
	for v in GEM_VERTICES:
		c += v
	return c / GEM_VERTICES.size()


## Outward unit normal of edge (a, b) — picked by pointing away from the
## polygon's own centroid, so this works regardless of the vertex winding
## order (a proper convex-polygon SDF needs no assumption about CW/CCW).
static func _gem_edge_normal(a: Vector2, b: Vector2, centroid: Vector2) -> Vector2:
	var d := b - a
	var n := Vector2(d.y, -d.x).normalized()
	if n.dot((a + b) * 0.5 - centroid) < 0.0:
		n = -n
	return n


## Signed distance from p to the nearest edge LINE of the convex
## [constant GEM_VERTICES] pentagon (positive = outside), that edge's outward
## normal, and the centroid-to-edge apothem — packed as a
## {"dist", "normal", "apothem"} Dictionary, mirroring sn_polygon_facet's
## per-sector packing but for an irregular convex polygon (edges vary in
## length/orientation, so "nearest edge" replaces "angle-fold sector"). For a
## convex shape, the point is inside iff every edge's signed distance is <= 0;
## the nearest edge is the one that's least negative (or positive, if outside).
static func _gem_nearest_edge(p: Vector2, centroid: Vector2) -> Dictionary:
	var best_dist := -INF
	var best_normal := Vector2.ZERO
	var best_apothem := 0.0
	var n_verts := GEM_VERTICES.size()
	for i in n_verts:
		var a: Vector2 = GEM_VERTICES[i]
		var b: Vector2 = GEM_VERTICES[(i + 1) % n_verts]
		var n := _gem_edge_normal(a, b, centroid)
		var edge_dist := (p - a).dot(n)
		if edge_dist > best_dist:
			best_dist = edge_dist
			best_normal = n
			best_apothem = (a - centroid).dot(n)
	return {"dist": best_dist, "normal": best_normal, "apothem": best_apothem}


## Side-view gem cut height/gradient at a normalized (-1..1) disk-space
## position — flat table facet (constant height, zero gradient) near the
## shape's own visual center, ramping linearly down to 0 at the outline
## (see GEM_TABLE_T). Same table+ramp convention the old top-view crown used,
## generalized from "radial distance in a regular polygon" to "distance to
## the nearest edge of an irregular convex polygon" (see _gem_nearest_edge).
## Returned as Vector3(drop, grad.x, grad.y); zero outside the shape.
static func _gem_height_grad(p: Vector2) -> Vector3:
	var centroid := _gem_centroid()
	var edge: Dictionary = _gem_nearest_edge(p, centroid)
	var edge_dist: float = edge["dist"]
	var apothem: float = edge["apothem"]
	if edge_dist > 0.0 or apothem <= 0.0:
		return Vector3.ZERO
	var t: float = clamp(edge_dist / apothem + 1.0, 0.0, 1.0)
	if t <= GEM_TABLE_T:
		return Vector3(GEM_DEPTH, 0.0, 0.0)
	var t2: float = (t - GEM_TABLE_T) / (1.0 - GEM_TABLE_T)
	var drop: float = GEM_DEPTH * (1.0 - t2)
	var slope := GEM_DEPTH / ((1.0 - GEM_TABLE_T) * apothem)
	var normal: Vector2 = edge["normal"]
	var grad := normal * -slope
	return Vector3(drop, grad.x, grad.y)


static func _gem_inside(p: Vector2) -> bool:
	var centroid := _gem_centroid()
	var edge: Dictionary = _gem_nearest_edge(p, centroid)
	return (edge["dist"] as float) <= 0.0
