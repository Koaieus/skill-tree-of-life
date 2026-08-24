@tool
class_name MinimapViewportRectLayer
extends Control

## The white outline showing what the main view currently covers (#453).
##
## Split out of [MinimapGraphLayer] because its cadence is the opposite: this
## moves on every pan and breathes through every zoom tween, while the graph
## underneath is static for whole turns at a time. One `draw_rect`.
##
## Holds a rect in MINIMAP-LOCAL space, not a camera — [MinimapPanel] owns the
## world mapping and the polling, so this layer has nothing to keep in sync.
##
## [b]The box is four filled spans, snapped to DEVICE pixel boundaries.[/b]
## Getting here took three passes, because each fix exposed the next cause:
##
##  1. A stroked `draw_rect` centres its hairline on the path, so an edge on a
##     pixel boundary covers half of each neighbouring column and reads as
##     nothing.
##  2. Snapping to whole LOCAL pixels does not fix that, because `project.godot`
##     sets `stretch/mode = "canvas_items"` against a 1440x960 base: at any
##     other window size the whole HUD is scaled by a non-integer factor, so one
##     local pixel is not one device pixel.
##  3. Nor does making each span one device pixel WIDE. Godot's 2D canvas does
##     not antialias filled geometry — a pixel is covered iff its CENTRE falls
##     inside the span. A span exactly one device pixel wide, landing halfway
##     between two centres, contains neither and draws nothing at all.
##
## (3) is what produced the reported symptom exactly: "fault lines" at a fixed
## set of screen positions, per axis, hitting all four edges — a vertical edge
## vanishing only at certain x, unaffected by vertical panning, and at the same
## x for the left and right side alike. That is a property of the coordinate,
## not of the edge.
##
## So the box is transformed into device space, snapped to integers there, and
## the spans are transformed back ([method _draw]). Each span then covers
## exactly one full pixel column or row and contains its centre by construction
## — at any window size, at every camera position.

@export var outline_color: Color = Color(1.0, 1.0, 1.0, 0.85)
@export var outline_width: float = 1.0

## Bumped on every `_draw`, the same way [MinimapGraphLayer] does it — so
## "an unchanged camera does not redraw" is an assertion rather than a claim.
var draw_count: int = 0

var _rect: Rect2 = Rect2()
var _has_rect: bool = false


## No-ops on an unchanged rect: the panel polls the camera every frame, and
## most frames it has not moved. Redrawing anyway would be cheap but would also
## make the whole "redraw only on change" split untestable.
##
## Snapping happens HERE rather than in [method _draw] so the comparison is
## made on the snapped value too — sub-pixel camera drift then lands on the
## same box and costs no redraw at all, which the raw rect never would.
func set_view_rect(rect: Rect2) -> void:
	var snapped_rect := _snap(rect)
	if _has_rect and snapped_rect.is_equal_approx(_rect):
		return
	_has_rect = true
	_rect = snapped_rect
	queue_redraw()


## Round the box to whole local pixels. This is NOT what makes the box render
## correctly — [method _draw] snaps in device space for that — it is purely the
## dedup key for [method set_view_rect], quantising sub-pixel camera drift so it
## costs no redraw.
##
## Safe as a dedup key at any canvas scale below 1 (one local pixel is then
## less than one device pixel, so no visible move can be quantised away). Above
## 1 the box can lag the camera by up to a device pixel for a frame, which is
## not worth a per-frame transform read to avoid.
func _snap(rect: Rect2) -> Rect2:
	return Rect2(rect.position.round(), rect.size.round().maxf(0.0))


## The box as four filled spans — top and bottom run the full width, the sides
## fill only what is left between them so the corners are not drawn twice (at
## this alpha a double-drawn corner is visibly brighter).
##
## Pure and static so the geometry is unit-testable without a viewport, a
## camera or a canvas scale.
static func _edge_rects(rect: Rect2, width: float) -> Array[Rect2]:
	var w := minf(width, minf(rect.size.x, rect.size.y) * 0.5)
	if w <= 0.0:
		return []
	var inner_height := maxf(rect.size.y - w * 2.0, 0.0)
	return [
		Rect2(rect.position.x, rect.position.y, rect.size.x, w),
		Rect2(rect.position.x, rect.end.y - w, rect.size.x, w),
		Rect2(rect.position.x, rect.position.y + w, w, inner_height),
		Rect2(rect.end.x - w, rect.position.y + w, w, inner_height),
	]


## Take the outline down — no camera bound, or a level with none at all.
func clear_view_rect() -> void:
	if not _has_rect:
		return
	_has_rect = false
	queue_redraw()


func _draw() -> void:
	draw_count += 1
	if not _has_rect:
		return
	var to_device := get_global_transform_with_canvas()
	# A degenerate transform means no viewport yet (a bare unit-test instance).
	# Draw in local space rather than dividing by a zero scale.
	if is_zero_approx(to_device.determinant()):
		for span in _edge_rects(_rect, outline_width):
			draw_rect(span, outline_color)
		return
	# Snap in DEVICE space so every span covers whole pixel columns/rows and
	# therefore contains their centres — see the class docs for why one device
	# pixel of WIDTH is not enough on its own.
	var device: Rect2 = to_device * _rect
	device = Rect2(device.position.round(), device.size.round().maxf(1.0))
	var to_local := to_device.affine_inverse()
	for span in _edge_rects(device, maxf(outline_width, 1.0)):
		draw_rect(to_local * span, outline_color)


## Dev dump for the system clipboard (`v` in [DebugClipboard]) — everything
## needed to replay one exact on-screen situation: the window's scaling, the
## camera, the minimap's mapping, and the DEVICE-space spans this layer is
## actually about to rasterise.
##
## The last part is the point. A missing side is a question about device
## coordinates, and reading them off a screenshot is guesswork; this prints
## them, plus which sides fail the "contains a pixel centre" test that decides
## whether a span renders at all.
func debug_state(camera: GraphCamera, panel: Control) -> String:
	var lines: PackedStringArray = []
	lines.append("MinimapViewportRect")
	var window := DisplayServer.window_get_size()
	lines.append("  window: %dx%d" % [window.x, window.y])
	lines.append("  content_scale_size: %s  factor: %.4f  stretch: %s" % [
			get_tree().root.content_scale_size,
			get_tree().root.content_scale_factor,
			get_tree().root.content_scale_mode])
	if camera != null:
		lines.append("  camera pos: (%.4f, %.4f)  zoom: (%.4f, %.4f)" % [
				camera.global_position.x, camera.global_position.y,
				camera.zoom.x, camera.zoom.y])
		lines.append("  camera view_rect: %s" % camera.view_rect())
	if panel != null:
		lines.append("  world_bounds: %s" % panel._world_bounds)
		lines.append("  map_scale: %.6f  map_offset: %s" % [panel._map_scale, panel._map_offset])
	lines.append("  layer size: %s" % size)
	lines.append("  local rect: %s  has_rect: %s" % [_rect, _has_rect])
	var xf := get_global_transform_with_canvas()
	lines.append("  to_device: origin=%s scale=%s" % [xf.origin, xf.get_scale()])
	if _has_rect and not is_zero_approx(xf.determinant()):
		var device: Rect2 = xf * _rect
		lines.append("  device rect (raw):    %s" % device)
		var snapped := Rect2(device.position.round(), device.size.round().maxf(1.0))
		lines.append("  device rect (snapped): %s" % snapped)
		var names := ["top", "bottom", "left", "right"]
		var spans := _edge_rects(snapped, maxf(outline_width, 1.0))
		if spans.is_empty():
			lines.append("  spans: NONE (degenerate box)")
		for i in spans.size():
			var span: Rect2 = spans[i]
			lines.append("    %-6s device %s -> covers a pixel centre: %s" % [
					names[i], span, _covers_a_pixel_centre(span)])
	return "\n".join(lines)


## Does this device-space span contain the centre of any pixel? Godot's 2D
## canvas does not antialias filled geometry, so a span that contains no pixel
## centre rasterises to nothing at all — which is exactly how a side goes
## missing while every number involved still looks reasonable.
static func _covers_a_pixel_centre(span: Rect2) -> bool:
	var first_x := floorf(span.position.x - 0.5) + 0.5
	if first_x < span.position.x:
		first_x += 1.0
	var first_y := floorf(span.position.y - 0.5) + 0.5
	if first_y < span.position.y:
		first_y += 1.0
	return first_x < span.end.x and first_y < span.end.y
