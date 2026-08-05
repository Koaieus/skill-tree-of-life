@tool
extends SkillNodeVisual
## Inner disk: semi-sphere `canvas_item` shader (#123). Filled circle with an
## offset radial highlight, lit in the entity's color when allocated and in a
## dark neutral when not — the dome, its shine and its carve dent draw either
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
## Composes the carve glyph directly as a height-field dent in its own shader
## (see inner_disk.gdshader's carve_kind/carve_* uniforms and
## lighting.gdshaderinc's sn_polygon_facet/sn_bowl_drop) rather than as a
## separate sibling node — the glyph used to be a Node2D with its own CPU twin
## of this shading formula; folding it into this same fragment shader means it
## can't drift from the disk's own lighting, by construction. See
## .claude/rules/skill-node-visuals.md.

const EmblemSpec = preload("res://skill_node/visuals/emblem/emblem_spec.gd")
const SHADER := preload("res://skill_node/visuals/inner_disk.gdshader")

## Which CARVE shape family the disk etches — the single selector replacing
## the retired pair of mutually-exclusive "show this glyph" bools (see
## .claude/rules/skill-node-visuals.md and [method set_carve]).
enum CarveKind { NONE, POLYGON, GEM, TEXTURE }

static var _shared_material: ShaderMaterial

## Loot relic gem cut (#168), viewed from the SIDE — flat table facet at top,
## tapering shoulders down to the widest girdle, then a pavilion tapering to a
## single point at the bottom (not the top-down radially-symmetric crown this
## used to bake). Baked ONCE into a small shared LUT (see _build_gem_lut)
## rather than recomputed per-pixel per-instance like the polygon carve — every
## relic wants the exact same cut, so there's nothing to gain from re-deriving
## it analytically on every node, every frame. Geometry constants here MUST
## mirror lighting.gdshaderinc's SN_GEM_DEPTH_SCALE / SN_GEM_GRAD_SCALE (the
## bake and the decode are two halves of one encoding).
const GEM_LUT_SIZE := 128

# --- Cut proportions -------------------------------------------------------
# A gem's side-view silhouette is fully specified by three ratios against the
# girdle DIAMETER — table width, crown height, pavilion depth. Deriving the
# vertices from those (rather than hardcoding y-coordinates, as this did until
# the gem pass) is what makes the shape tunable and self-documenting: the old
# numbers gave a 41%-wide table, which is what made it read as a kite rather
# than a gem.
#
# These defaults target the DIAMOND-EMOJI read (wide table, modest crown, deep
# pointed pavilion, near-square aspect) rather than gemology's Tolkowsky ideal
# cut (table 53-58%, crown 16.2%, pavilion 43.1% — a real brilliant is far
# squatter than the icon everyone pictures). If you want the true ideal cut,
# those are the three numbers to drop in; the geometry needs no other change.
#
# Everything below is in DISK SPACE: the -1..1 square the shader's `p` spans,
# with +Y DOWN (Godot screen convention, matching the LUT image rows the bake
# writes and the `UV` the shader samples with). Author y-values here as they
# should APPEAR — the table on top, the culet below. See _build_gem_lut.
## Girdle (widest point) half-width. The one free scale knob; everything else
## is a ratio off it. Sized so the girdle corners sit at ~0.85 of the disk
## radius, leaving the dome's edge falloff room to breathe.
const GEM_GIRDLE_HALF_WIDTH := 0.82
## Table (flat top facet) width as a fraction of girdle diameter.
const GEM_TABLE_RATIO := 0.58
## Crown height (table→girdle) as a fraction of girdle diameter.
const GEM_CROWN_RATIO := 0.25
## Pavilion depth (girdle→culet) as a fraction of girdle diameter. Much deeper
## than the crown is tall — that asymmetry is most of what makes a shape read
## as "gem" rather than "hexagon".
const GEM_PAVILION_RATIO := 0.60

const GEM_TABLE_HALF_WIDTH := GEM_GIRDLE_HALF_WIDTH * GEM_TABLE_RATIO
const GEM_CROWN_HEIGHT := 2.0 * GEM_GIRDLE_HALF_WIDTH * GEM_CROWN_RATIO
const GEM_PAVILION_DEPTH := 2.0 * GEM_GIRDLE_HALF_WIDTH * GEM_PAVILION_RATIO
## Vertically centred on the disk: half the total depth sits above y=0.
const GEM_TABLE_Y := -(GEM_CROWN_HEIGHT + GEM_PAVILION_DEPTH) * 0.5
const GEM_GIRDLE_Y := GEM_TABLE_Y + GEM_CROWN_HEIGHT
const GEM_CULET_Y := GEM_GIRDLE_Y + GEM_PAVILION_DEPTH

## Fraction of the interior→boundary ramp that stays flat (the table facet).
const GEM_TABLE_T := 0.15
const GEM_DEPTH := 0.35
const GEM_GRAD_SCALE := 3.0
## Width (in LUT texels) of the antialiasing band smeared across the
## silhouette's edge by the alpha channel. The LUT is minified ~2x on screen
## (128px LUT, ~48-64px disk), so ~2.5 texels lands at roughly one screen
## pixel of coverage falloff. See _build_gem_lut's alpha and the shader's
## blend (inner_disk.gdshader) — a HARD alpha here plus a `> 0.5` branch there
## is what made the gem's outline stair-step.
const GEM_EDGE_AA_TEXELS := 2.5

## The side-view silhouette: flat TOP edge (the table), tapering shoulders out
## to the girdle (widest point), then a pavilion tapering down to the culet
## point. +Y is down, so the table's y is the most negative.
const GEM_VERTICES := [
	Vector2(GEM_TABLE_HALF_WIDTH, GEM_TABLE_Y),
	Vector2(-GEM_TABLE_HALF_WIDTH, GEM_TABLE_Y),
	Vector2(-GEM_GIRDLE_HALF_WIDTH, GEM_GIRDLE_Y),
	Vector2(0.0, GEM_CULET_Y),
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

## The carve this disk renders when nothing has RESOLVED one yet — the
## authored default / standalone preview, expressed as the shape itself
## (a shared `emblem/shapes/*.tres` or any authored [CarveShape]). Null =
## the empty dome, per the locked design ("showWeld — off is the new default;
## empty center. on restores the archetype shape" — Rim Forge Lab): the disk's
## own semi-sphere shading + specular highlight is the baseline read, a carve
## is an opt-in accent. See .claude/rules/skill-node-visuals.md and
## [method set_carve].
##
## Once [method set_carve] has run, the resolved shape wins and this authored
## value is left untouched (see [member _carved_shape]).
@export var carve_shape: CarveShape = null:
	set(value):
		if carve_shape == value:
			return
		carve_shape = value
		_sync_material()

## Max depth of the glyph's bowl dent at its own visual center — see
## inner_disk.gdshader/lighting.gdshaderinc's sn_bowl_drop. Unlike the knobs
## above this one is a genuine STYLE dial ("how carved does this game look"),
## so a carved shape only supersedes it when it explicitly opts in — see
## [member PolygonCarveShape.well_depth].
@export_range(0.0, 1.0, 0.01) var well_depth: float = 0.35:
	set(value):
		well_depth = value
		_sync_material()

# ── Resolved carve: runtime state, deliberately NOT exported ──────────────────
#
# [method set_carve] writes ONLY these. Writing the resolved shape back into an
# @export (or pushing it into [member carve_shape]) is the "a @tool script must
# never write a DERIVED value into an @export" trap
# (.claude/rules/godot-workflow.md) — the editor serialises the computed value
# into the .tscn, and the next load computes again from there.

## The shape of the last resolved carve — the [CarveShape] itself (#315), so a
## new shape parameter is one edit on the shape rather than another copy hop
## here. Null is meaningful: "a carve resolved, and it has no shape" (an empty
## dome), which is why [member _has_carve] is a separate flag.
var _carved_shape: CarveShape = null
## Whether [method set_carve] has ever run. Distinguishes "nothing has resolved
## a carve yet" (fall back to the authored [member carve_shape]) from "a carve
## resolved to nothing" (an honest empty dome).
var _has_carve: bool = false

## The shape that actually renders: the resolved runtime carve once
## [method set_carve] has run, else the authored [member carve_shape].
func _effective_shape() -> CarveShape:
	return _carved_shape if _has_carve else carve_shape


## The carve family actually rendered: the resolved shape's own family once a
## carve has been pushed, else the authored [member carve_shape]'s family.
## Mapping a shape family to a [enum CarveKind] is THIS renderer's job —
## `skill_node/visuals/emblem/` deliberately knows nothing about InnerDisk.
var effective_carve_kind: CarveKind:
	get:
		var shape := _effective_shape()
		if shape is PolygonCarveShape:
			return CarveKind.POLYGON
		if shape is GemCarveShape:
			return CarveKind.GEM
		if shape is TextureCarveShape:
			# A baked LUT the atlas doesn't carry degrades to the empty dome
			# rather than rendering some other node's glyph; set_carve warns.
			return CarveKind.TEXTURE if effective_carve_slice != CarveAtlas.NO_SLICE else CarveKind.NONE
		# Including a null shape: an empty dome is the honest fallback rather
		# than misrepresenting the node as its archetype shape when a
		# higher-priority carve won.
		return CarveKind.NONE

## Which [CarveAtlas] slice a TEXTURE carve reads, or [constant
## CarveAtlas.NO_SLICE]. Derived from the shape's baked LUT rather than
## authored anywhere: the packing order is the generator's to decide, so a
## hand-written index is a second copy of it that can silently drift.
##
## This is the per-node value that makes arbitrary art possible at all. A
## sampler can't be an `instance uniform`, so every baked LUT lives in ONE
## array texture on the shared material and only this int varies — which is
## what keeps InnerDisk's single-draw-call batching, and why adding shapes
## costs slices instead of #172's instance-uniform slots.
var effective_carve_slice: int:
	get:
		var shape := _effective_shape()
		if shape is TextureCarveShape:
			var atlas := CarveAtlas.shared()
			if atlas != null:
				return atlas.slice_of((shape as TextureCarveShape).baked_lut)
		return CarveAtlas.NO_SLICE

var effective_carve_sides: int:
	get:
		var shape := _effective_shape()
		return (shape as PolygonCarveShape).sides if shape is PolygonCarveShape else 3

var effective_carve_squish: float:
	get:
		var shape := _effective_shape()
		return (shape as PolygonCarveShape).squish_x if shape is PolygonCarveShape else 1.0

var effective_carve_radius: float:
	get:
		var shape := _effective_shape()
		return (shape as PolygonCarveShape).radius if shape is PolygonCarveShape else 0.75

## Resolves [member PolygonCarveShape.well_depth]'s negative "inherit" sentinel
## on the CPU. This getter is the ONLY thing standing between that sentinel and
## a `hint_range(0.0, 1.0)` uniform that would clamp it to 0.0 — i.e. silently
## flatten the dent on every shape that inherits.
var effective_well_depth: float:
	get:
		var shape := _effective_shape()
		if shape is PolygonCarveShape:
			var override: float = (shape as PolygonCarveShape).well_depth
			if override >= 0.0:
				return override
		return well_depth

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
	# Same deal for the arbitrary-art atlas (#247): ONE array texture holding
	# every baked LUT, bound once on the shared material. Per-node variation is
	# the `carve_slice` index below, not the sampler — see [CarveAtlas].
	var atlas := CarveAtlas.shared()
	if atlas != null:
		_shared_material.set_shader_parameter(&"carve_atlas", atlas.texture())
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
	set_instance_shader_parameter(&"carve_kind", effective_carve_kind)
	set_instance_shader_parameter(&"carve_sides", float(effective_carve_sides))
	set_instance_shader_parameter(&"carve_squish", effective_carve_squish)
	set_instance_shader_parameter(&"carve_radius", effective_carve_radius)
	set_instance_shader_parameter(&"well_depth", effective_well_depth)
	set_instance_shader_parameter(&"carve_slice", effective_carve_slice)
	queue_redraw()


## Consumes a resolved central-emblem CARVE (docs/domain/skillnode-emblem.md) —
## the sanctioned entry point once a caller has an [EmblemResolver.Resolution].
## `carve` is the winning [EmblemSpec] (an [EmblemResolver] Resolution's
## `.carve`), or null for an empty dome.
##
## Keeps the [member EmblemSpec.shape] itself rather than copying its fields
## anywhere: every rendered value is derived from it on read (the `effective_*`
## getters above), which is both why adding a shape parameter costs one edit on
## the shape and how this stays clear of the "@tool script writes a derived
## value into an @export" trap. NOTHING exported is written here — see
## [member _carved_shape]. A [TextureCarveShape] (arbitrary baked art, #246)
## resolves to its [CarveAtlas] slice the same way, via
## [member effective_carve_slice].
func set_carve(carve: Variant) -> void:
	_carved_shape = carve.shape if carve != null else null
	_has_carve = true
	_warn_if_unpacked()
	_sync_material()


## Warns once per resolve when a [TextureCarveShape] carries a baked LUT the
## [CarveAtlas] doesn't have — an in-memory bake that was never committed, or
## one committed without re-running `mise run icons:update`. It's a real
## authoring mistake, and the render silently degrades to an empty dome, so it
## deserves a word. Lives HERE rather than in [member effective_carve_slice]
## because that getter is read on every `_sync_material()` and would spam.
func _warn_if_unpacked() -> void:
	if not _carved_shape is TextureCarveShape:
		return
	if effective_carve_slice != CarveAtlas.NO_SLICE:
		return
	var lut: Texture2D = (_carved_shape as TextureCarveShape).baked_lut
	if CarveAtlas.shared() == null:
		push_warning("InnerDisk: no CarveAtlas generated — run `mise run icons:update`")
	else:
		push_warning("InnerDisk: baked LUT '%s' is not in the CarveAtlas" % (lut.resource_path if lut != null else "<null>"))


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
## grad/GEM_GRAD_SCALE remapped -1..1 -> 0..1, A = the silhouette's ANTIALIASED
## coverage (1 well inside, ramping to 0 just outside — see [method
## _gem_coverage]), which the shader uses as a BLEND WEIGHT, never as a
## `> 0.5` cutoff.
##
## The bake walks image rows top-to-bottom, so `p` here is already in the
## same +Y-down space as the shader's `UV`-derived `p` — which is why
## [constant GEM_VERTICES] is authored with the table at NEGATIVE y. Feeding
## it math-convention (+Y up) vertices renders the gem culet-up; that was a
## real shipped bug, and it survived because the geometry unit tests all work
## in the same flipped space and are self-consistent inside it. The regression
## test that actually catches it measures the baked LUT's per-row alpha span.
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
			img.set_pixel(x, y, Color(r, g, b, _gem_coverage(p)))
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


## Antialiased silhouette coverage at `p`: 1 well inside the outline, 0 well
## outside, with a [constant GEM_EDGE_AA_TEXELS]-wide smoothstep across the
## boundary. This is the LUT's alpha channel, and the shader multiplies the
## gem's normal perturbation by it.
##
## A hard 0/1 alpha here was the gem's stair-stepped-outline bug: the mip
## chain does soften a binary edge, but the shader then threw that away with
## `if (lut.a > 0.5)`, snapping every partially-covered pixel back to fully
## in or fully out. Coverage must be smooth on BOTH sides of that boundary —
## a soft bake with a hard branch antialiases nothing.
static func _gem_coverage(p: Vector2) -> float:
	var centroid := _gem_centroid()
	var edge: Dictionary = _gem_nearest_edge(p, centroid)
	var dist: float = edge["dist"]
	# One LUT texel spans 2.0 / GEM_LUT_SIZE in the -1..1 disk space `p` uses.
	var band := GEM_EDGE_AA_TEXELS * 2.0 / float(GEM_LUT_SIZE)
	return smoothstep(band * 0.5, -band * 0.5, dist)
