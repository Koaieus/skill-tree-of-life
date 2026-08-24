@tool
class_name MinimapGraphLayer
extends Control

## The dot-and-edge layer of the minimap (#453). Deliberately dumb: it owns no
## graph reference, no mapping and no schedule — [MinimapPanel] builds the
## point/colour arrays in minimap-local space and pushes them here.
##
## [b]Why it is its own Control[/b]: this is the layer whose redraw is
## expensive (a level holds 500–2500 SkillNodes) and whose content is nearly
## static — it changes on allocation and on topology, not on camera motion.
## The viewport outline is the opposite on both counts. Splitting them is what
## keeps a pan from re-walking the whole graph every frame; see
## docs/domain/rendering-performance.md.
##
## Both arrays are drawn with ONE `draw_multiline_colors` call each, so the
## whole board costs two draw calls regardless of node count. Node dots are
## short segments (length == width) rather than `draw_circle` calls for exactly
## that reason — a per-node call would be 2500 of them.

## Bumped on every `_draw`. Exists so the redraw-cadence claim above is an
## assertion in `test/unit/ui/test_minimap_panel.gd` rather than a comment —
## a temporary `print` you have to remember to delete proves nothing later.
var draw_count: int = 0

var _edge_points: PackedVector2Array = PackedVector2Array()
var _edge_colors: PackedColorArray = PackedColorArray()
var _dot_points: PackedVector2Array = PackedVector2Array()
var _dot_colors: PackedColorArray = PackedColorArray()
var _edge_width: float = 1.0
var _dot_size: float = 2.0


## Replace what this layer draws. Called by [MinimapPanel] whenever the graph
## or its ownership changed — never on camera motion.
func set_geometry(
	edge_points: PackedVector2Array,
	edge_colors: PackedColorArray,
	dot_points: PackedVector2Array,
	dot_colors: PackedColorArray,
	edge_width: float,
	dot_size: float,
) -> void:
	_edge_points = edge_points
	_edge_colors = edge_colors
	_dot_points = dot_points
	_dot_colors = dot_colors
	_edge_width = edge_width
	_dot_size = dot_size
	queue_redraw()


func _draw() -> void:
	draw_count += 1
	# `draw_multiline_colors` wants exactly one colour per SEGMENT, i.e. per
	# point PAIR. A mismatch draws nothing at all rather than erroring, so the
	# guard is worth its two lines.
	if _edge_points.size() >= 2 and _edge_colors.size() == _edge_points.size() / 2:
		draw_multiline_colors(_edge_points, _edge_colors, _edge_width)
	if _dot_points.size() >= 2 and _dot_colors.size() == _dot_points.size() / 2:
		draw_multiline_colors(_dot_points, _dot_colors, _dot_size)
