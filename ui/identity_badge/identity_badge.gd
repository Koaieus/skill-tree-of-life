@tool
class_name IdentityBadge
extends Control

## An [Identity] as a glyph: the kind's frame polygon ([BadgeFrames]) stroked
## around the identity's icon — or, with no icon, its noun's first letter (the
## one place that letter fallback lives) — all in the identity tint lifted
## through [method Emissive.at] at [member emissive_tier]. Plain `_draw`, no
## material, so hundreds batch (`rendering-performance.md`).
##
## [method composite] bakes the same silhouette in white for consumers that
## need a texture (inline text images) and supply the hue themselves.

## The identity shown; null draws nothing.
@export var identity: Identity:
	set(value):
		if identity == value:
			return
		if identity != null and identity.changed.is_connected(queue_redraw):
			identity.changed.disconnect(queue_redraw)
		identity = value
		if identity != null:
			identity.changed.connect(queue_redraw)
		queue_redraw()
## How lit the badge reads; the identity stores its hue unlifted.
@export var emissive_tier: Emissive.Tier = Emissive.Tier.LABEL:
	set(value):
		emissive_tier = value
		queue_redraw()
## Edge length of the square badge.
@export_range(12, 128) var size_px: int = 24:
	set(value):
		size_px = value
		update_minimum_size()
		queue_redraw()

## Test hook: the colour of the last draw; transparent until something drew.
var last_draw_color := Color.TRANSPARENT

## White composites by "<id>@<size>". Cleared by [method clear_cache].
static var _cache: Dictionary[String, ImageTexture] = {}
static var _fonts: Dictionary[String, Font] = {}


func _ready() -> void:
	var frames := BadgeFrames.shared()
	if frames != null and not frames.changed.is_connected(queue_redraw):
		frames.changed.connect(queue_redraw)


func _get_minimum_size() -> Vector2:
	return Vector2(size_px, size_px)


func _draw() -> void:
	if identity == null:
		return
	var frames := BadgeFrames.shared()
	var color := Emissive.at(identity.tint, Emissive.stops(emissive_tier))
	last_draw_color = color
	var side := minf(size.x, size.y) if size.x > 0.0 and size.y > 0.0 else float(size_px)
	var origin := (size - Vector2(side, side)) * 0.5
	var center := origin + Vector2(side, side) * 0.5
	var points := frames.frame_for(identity.kind).vertices(center, side * 0.5 - frames.stroke_px * 0.5)
	points.append(points[0])
	draw_polyline(points, color, frames.stroke_px, true)
	var box := _content_rect(origin, side, frames.icon_inset)
	if identity.icon != null:
		draw_texture_rect(identity.icon, _fit(box, identity.icon.get_size()), false, color)
		return
	var font := _letter_font(get_theme_default_font(), frames.letter_embolden)
	var letter := letter_of(identity)
	var font_size := _letter_font_size(box)
	var glyph := _glyph_bounds(font, letter, font_size)
	var baseline := Vector2(box.position.x, center.y - glyph.get_center().y)
	draw_string(font, baseline, letter, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, font_size, color)


## The fallback glyph: the noun's first letter, upper-cased; "?" for no noun.
static func letter_of(of: Identity) -> String:
	return of.noun.substr(0, 1).to_upper() if of.noun != "" else "?"


## Drop every baked composite (after a [BadgeFrames] or identity edit).
static func clear_cache() -> void:
	_cache.clear()


## Frame ∪ (icon | letter) as a white silhouette, `size_px` square, baked once
## per `(identity.id, size_px)` — the caller tints it (e.g. `add_image`'s
## colour). Null for a null identity.
static func composite(of: Identity, size_px: int) -> ImageTexture:
	if of == null or size_px <= 0:
		return null
	var key := "%s@%d" % [of.id, size_px]
	if _cache.has(key):
		return _cache[key]
	var frames := BadgeFrames.shared()
	var mask := PackedFloat32Array()
	mask.resize(size_px * size_px)
	var side := float(size_px)
	var half := Vector2(side, side) * 0.5
	_stamp_stroke(mask, size_px, frames.frame_for(of.kind).vertices(half, side * 0.5 - frames.stroke_px * 0.5), frames.stroke_px)
	var box := _content_rect(Vector2.ZERO, side, frames.icon_inset)
	var content := _icon_image(of.icon, box) if of.icon != null else _letter_image(letter_of(of), box, frames.letter_embolden)
	if content != null:
		_stamp_image(mask, size_px, content, Vector2i((box.position + (box.size - Vector2(content.get_size())) * 0.5).round()))
	var image := Image.create_empty(size_px, size_px, false, Image.FORMAT_RGBA8)
	for y in size_px:
		for x in size_px:
			image.set_pixel(x, y, Color(1, 1, 1, mask[y * size_px + x]))
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


static func _content_rect(origin: Vector2, side: float, inset: float) -> Rect2:
	var margin := side * inset
	return Rect2(origin + Vector2(margin, margin), Vector2(side, side) - Vector2(margin, margin) * 2.0)


## `content` scaled to fit `box`, aspect kept, centred.
static func _fit(box: Rect2, content: Vector2) -> Rect2:
	if content.x <= 0.0 or content.y <= 0.0:
		return box
	var scale := minf(box.size.x / content.x, box.size.y / content.y)
	var fitted := content * scale
	return Rect2(box.position + (box.size - fitted) * 0.5, fitted)


## `base` emboldened so the letter's weight sits with the frame stroke; one
## [FontVariation] per (font, embolden).
static func _letter_font(base: Font, embolden: float) -> Font:
	if is_zero_approx(embolden):
		return base
	var key := "%d@%.3f" % [base.get_instance_id(), embolden]
	if not _fonts.has(key):
		var variation := FontVariation.new()
		variation.base_font = base
		variation.variation_embolden = embolden
		_fonts[key] = variation
	return _fonts[key]


## Font size whose capital roughly fills the box height.
static func _letter_font_size(box: Rect2) -> int:
	return maxi(6, int(round(box.size.y * 1.35)))


## The glyph's ink rect relative to the baseline origin, at `font_size`.
static func _glyph_bounds(font: Font, letter: String, font_size: int) -> Rect2:
	var ts := TextServerManager.get_primary_interface()
	var rid: RID = font.get_rids()[0]
	var glyph := ts.font_get_glyph_index(rid, font_size, letter.unicode_at(0), 0)
	var size := Vector2i(font_size, 0)
	return Rect2(ts.font_get_glyph_offset(rid, size, glyph), ts.font_get_glyph_size(rid, size, glyph))


## Anti-aliased stroke of the closed polygon `points` into `mask` (coverage
## from each pixel centre's distance to the outline).
static func _stamp_stroke(mask: PackedFloat32Array, size_px: int, points: PackedVector2Array, stroke: float) -> void:
	var reach := stroke * 0.5 + 0.5
	for y in size_px:
		for x in size_px:
			var p := Vector2(x + 0.5, y + 0.5)
			var best := INF
			for i in points.size():
				var on := Geometry2D.get_closest_point_to_segment(p, points[i], points[(i + 1) % points.size()])
				best = minf(best, p.distance_to(on))
			var alpha := clampf(reach - best, 0.0, 1.0)
			var at := y * size_px + x
			mask[at] = maxf(mask[at], alpha)


static func _stamp_image(mask: PackedFloat32Array, size_px: int, content: Image, at: Vector2i) -> void:
	for y in content.get_height():
		for x in content.get_width():
			var px := at + Vector2i(x, y)
			if px.x < 0 or px.y < 0 or px.x >= size_px or px.y >= size_px:
				continue
			var i := px.y * size_px + px.x
			mask[i] = maxf(mask[i], content.get_pixel(x, y).a)


## The icon's alpha, fitted into `box`.
static func _icon_image(icon: Texture2D, box: Rect2) -> Image:
	var image := icon.get_image()
	if image == null:
		return null
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var fitted := _fit(box, Vector2(image.get_size())).size
	image.resize(maxi(1, roundi(fitted.x)), maxi(1, roundi(fitted.y)), Image.INTERPOLATE_BILINEAR)
	return image


## The letter's coverage bitmap from the theme body font's glyph cache,
## fitted into `box`.
static func _letter_image(letter: String, box: Rect2, embolden: float) -> Image:
	var theme := ThemeDB.get_project_theme()
	var base: Font = theme.default_font if theme != null and theme.default_font != null else ThemeDB.fallback_font
	var font := _letter_font(base, embolden)
	var ts := TextServerManager.get_primary_interface()
	var rid: RID = font.get_rids()[0]
	var font_size := _letter_font_size(box)
	var size := Vector2i(font_size, 0)
	var glyph := ts.font_get_glyph_index(rid, font_size, letter.unicode_at(0), 0)
	ts.font_render_glyph(rid, size, glyph)
	var page := ts.font_get_glyph_texture_idx(rid, size, glyph)
	if page < 0:
		return null
	var crop := ts.font_get_texture_image(rid, size, page).get_region(Rect2i(ts.font_get_glyph_uv_rect(rid, size, glyph)))
	crop.convert(Image.FORMAT_RGBA8)
	if ts.font_is_multichannel_signed_distance_field(rid):
		for y in crop.get_height():
			for x in crop.get_width():
				var c := crop.get_pixel(x, y)
				var median := maxf(minf(c.r, c.g), minf(maxf(c.r, c.g), c.b))
				crop.set_pixel(x, y, Color(1, 1, 1, 1.0 if median >= 0.5 else 0.0))
	var fitted := _fit(box, Vector2(crop.get_size())).size
	crop.resize(maxi(1, roundi(fitted.x)), maxi(1, roundi(fitted.y)), Image.INTERPOLATE_BILINEAR)
	return crop
