@tool
class_name TextureCarveShape
extends CarveShape
## Arbitrary-art CARVE (#246) — bakes an authored icon's alpha silhouette
## into the same height+gradient LUT encoding InnerDisk's gem carve already
## uses (mirrors `InnerDisk._build_gem_lut` / `sn_gem_bump` exactly; see
## docs/domain/emblem-bake.md for the derivation and the note that #247's
## shader decode constants must stay in lock-step with the ones below).
##
## OFFLINE BAKE ONLY. This shape carries the baked LUT, not the raw icon, and
## rides into the [EmblemSpec] as itself (#315) — so #247's decode reads
## [member baked_lut] straight off the shape. No live-render decode exists yet;
## until then InnerDisk falls back to an empty dome for this shape family (see
## .claude/rules/skill-node-visuals.md).
##
## Source icons (`assets/icons/spells/*.png`) are flat monochrome silhouettes
## with the background alpha-stripped — luminance carries no interior height,
## so only alpha is meaningful. Pipeline: source alpha -> inside-mask
## (threshold) -> distance transform of the mask -> drop as a function of
## distance-to-edge (deepest interior, ramping to 0 at the silhouette edge,
## an intaglio dent) -> gradient by finite difference of the drop field.

## CARVE LUT resolution, shared with the SVG pipeline in tools/bake_svg_sdf.py
## (keep the two in lock-step — the atlas packs by this size). The gem LUT is
## deliberately its own size (GEM_LUT_SIZE on InnerDisk); the two samplers are
## independent and the decode side only reads depth/gradient constants.
const LUT_SIZE := 256
## Max dent depth, R-channel divisor. Mirror in #247's decode constants.
const DEPTH := 0.35
## Gradient magnitude divisor for the -1..1 -> 0..1 GB remap. Mirror in #247's
## decode constants.
const GRAD_SCALE := 3.0
## Source alpha above this counts as "inside" the silhouette.
const ALPHA_THRESHOLD := 0.5
## Texels per unit of `p` — the LUT spans the disk's −1..1 space, so one texel
## is `2 / LUT_SIZE` wide and there are `LUT_SIZE / 2` of them per unit. This is
## the unit conversion that makes [method _gradient_at]'s finite differences
## comparable to the shader's own `-p / z_dome`; see #318.
const TEXELS_PER_UNIT_P := LUT_SIZE * 0.5

## The authored icon to bake. Only its ALPHA channel is read (see class doc).
@export var source_texture: Texture2D

## The baked LUT this shape carries. Set by [method _bake_from_source] (the tool
## button) or assigned directly (e.g. loading a committed asset).
@export var baked_lut: Texture2D

@export_tool_button("Bake") var bake_button: Callable = _bake_from_source


func _bake_from_source() -> void:
	if source_texture == null:
		push_warning("TextureCarveShape.bake: no source_texture set")
		return
	if baked_lut != null and not baked_lut.resource_path.is_empty():
		push_warning(
			"TextureCarveShape.bake: refusing to overwrite committed LUT %s — "
			% baked_lut.resource_path
			+ "pipeline LUTs are baked from the SVG (tools/bake_svg_sdf.py) and must not "
			+ "be swapped for a raster chamfer bake. Clear baked_lut first if you really "
			+ "want to re-bake from source_texture."
		)
		return
	baked_lut = bake_lut(source_texture)


## Headless-callable bake — [member bake_button] above is a thin wrapper over
## this so a test (or a CLI batch re-bake) can drive it without the editor.
## Deterministic: baking the same source twice yields byte-identical images,
## which is what makes the committed asset in assets/emblem_luts/ reproducible.
static func bake_lut(source: Texture2D) -> ImageTexture:
	var src_img := source.get_image()
	src_img = src_img.duplicate()
	if src_img.is_compressed():
		src_img.decompress()
	if src_img.get_format() != Image.FORMAT_RGBA8:
		src_img.convert(Image.FORMAT_RGBA8)

	var mask := _build_inside_mask(src_img)
	var dist := _distance_transform(mask)
	var drop_field := _build_drop_field(mask, dist)

	var img := Image.create(LUT_SIZE, LUT_SIZE, false, Image.FORMAT_RGBA8)
	for y in LUT_SIZE:
		for x in LUT_SIZE:
			var idx := y * LUT_SIZE + x
			var drop: float = drop_field[idx]
			var grad := _gradient_at(drop_field, x, y)
			var r := clampf(drop / DEPTH, 0.0, 1.0)
			var g := clampf(grad.x / GRAD_SCALE * 0.5 + 0.5, 0.0, 1.0)
			var b := clampf(grad.y / GRAD_SCALE * 0.5 + 0.5, 0.0, 1.0)
			var a := 1.0 if bool(mask[idx]) else 0.0
			img.set_pixel(x, y, Color(r, g, b, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Nearest-sampled alpha->bool mask at LUT resolution — true where the source
## icon's alpha is above [constant ALPHA_THRESHOLD]. Nearest (not bilinear) so
## the silhouette boundary stays a crisp threshold, not a blurred one.
static func _build_inside_mask(src_img: Image) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(LUT_SIZE * LUT_SIZE)
	var sw := src_img.get_width()
	var sh := src_img.get_height()
	for y in LUT_SIZE:
		var v := (float(y) + 0.5) / float(LUT_SIZE)
		var sy: int = clampi(int(v * sh), 0, sh - 1)
		for x in LUT_SIZE:
			var u := (float(x) + 0.5) / float(LUT_SIZE)
			var sx: int = clampi(int(u * sw), 0, sw - 1)
			var inside := src_img.get_pixel(sx, sy).a > ALPHA_THRESHOLD
			mask[y * LUT_SIZE + x] = 1 if inside else 0
	return mask


## Approximate Euclidean distance transform (two-pass chamfer, 1/sqrt(2)
## weights) — for every INSIDE texel, the distance in texels to the nearest
## OUTSIDE texel; 0 for outside texels themselves. Deterministic, O(N), no
## per-boundary-pixel brute force. Standard two-pass chamfer technique: seed
## outside texels at 0, propagate forward (top-left -> bottom-right) then
## backward (bottom-right -> top-left) over the 8-neighborhood.
static func _distance_transform(mask: PackedByteArray) -> PackedFloat32Array:
	const INF := 1e9
	const ORTHO := 1.0
	const DIAG := 1.41421356
	var dist := PackedFloat32Array()
	dist.resize(LUT_SIZE * LUT_SIZE)
	for i in dist.size():
		dist[i] = 0.0 if mask[i] == 0 else INF

	for y in LUT_SIZE:
		for x in LUT_SIZE:
			var idx := y * LUT_SIZE + x
			var d: float = dist[idx]
			if x > 0:
				d = minf(d, dist[idx - 1] + ORTHO)
			if y > 0:
				d = minf(d, dist[idx - LUT_SIZE] + ORTHO)
				if x > 0:
					d = minf(d, dist[idx - LUT_SIZE - 1] + DIAG)
				if x < LUT_SIZE - 1:
					d = minf(d, dist[idx - LUT_SIZE + 1] + DIAG)
			dist[idx] = d

	for y in range(LUT_SIZE - 1, -1, -1):
		for x in range(LUT_SIZE - 1, -1, -1):
			var idx := y * LUT_SIZE + x
			var d: float = dist[idx]
			if x < LUT_SIZE - 1:
				d = minf(d, dist[idx + 1] + ORTHO)
			if y < LUT_SIZE - 1:
				d = minf(d, dist[idx + LUT_SIZE] + ORTHO)
				if x < LUT_SIZE - 1:
					d = minf(d, dist[idx + LUT_SIZE + 1] + DIAG)
				if x > 0:
					d = minf(d, dist[idx + LUT_SIZE - 1] + DIAG)
			dist[idx] = d

	return dist


## drop(distance-to-edge), normalized per-icon: 0 at the silhouette boundary,
## ramping to [constant DEPTH] at the texel(s) farthest from any edge (the
## shape's medial axis). Outside texels are 0.
static func _build_drop_field(mask: PackedByteArray, dist: PackedFloat32Array) -> PackedFloat32Array:
	var max_dist := 0.0
	for i in dist.size():
		if mask[i] != 0:
			max_dist = maxf(max_dist, dist[i])

	var drop := PackedFloat32Array()
	drop.resize(mask.size())
	if max_dist <= 0.0:
		return drop
	for i in drop.size():
		if mask[i] != 0:
			drop[i] = DEPTH * clampf(dist[i] / max_dist, 0.0, 1.0)
	return drop


## Central-difference gradient of the drop field at texel (x, y), one-sided
## at the LUT's own border.
##
## Units: **drop-per-unit-p**, matching [code]inner_disk.gdshader[/code]'s own
## [code]grad_dome = -p / z_dome[/code], which lives in the −1..1 disk space.
## The finite differences below are naturally drop-per-TEXEL, so they're scaled
## by [constant TEXELS_PER_UNIT_P] on the way out. Getting this wrong is silent:
## both halves of the encoding agree on the divisor and disagree on what the
## numerator means, so the bake stays in range, every GB texel lands on ~0.5
## (neutral), and the carve renders as a blank dome. See #318.
static func _gradient_at(drop_field: PackedFloat32Array, x: int, y: int) -> Vector2:
	var idx := y * LUT_SIZE + x
	var gx: float
	if x > 0 and x < LUT_SIZE - 1:
		gx = (drop_field[idx + 1] - drop_field[idx - 1]) * 0.5
	elif x < LUT_SIZE - 1:
		gx = drop_field[idx + 1] - drop_field[idx]
	else:
		gx = drop_field[idx] - drop_field[idx - 1]

	var gy: float
	if y > 0 and y < LUT_SIZE - 1:
		gy = (drop_field[idx + LUT_SIZE] - drop_field[idx - LUT_SIZE]) * 0.5
	elif y < LUT_SIZE - 1:
		gy = drop_field[idx + LUT_SIZE] - drop_field[idx]
	else:
		gy = drop_field[idx] - drop_field[idx - LUT_SIZE]

	return Vector2(gx, gy) * TEXELS_PER_UNIT_P
