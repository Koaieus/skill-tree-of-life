extends GutTest

## A [Banner] spans the full canvas width, and must still do so when its
## anchors arrive zeroed — which is exactly what an export does to it
## (`anchors_preset = 0` is written into the re-saved binary scene, and the
## `anchor_right = 1.0` that would undo it is dropped as redundant against
## `banner.tscn`'s own root). Source runs and this test both load the band
## intact, so the zeroing has to be applied by hand for the regression to have
## anything to catch.

const BANNER := preload("res://ui/banner_layer/banner.tscn")

var _layer: CanvasLayer


func before_each() -> void:
	_layer = CanvasLayer.new()
	add_child_autofree(_layer)


func _add_band(zero_anchors: bool) -> Banner:
	var band: Banner = BANNER.instantiate()
	if zero_anchors:
		band.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_layer.add_child(band)
	return band


func test_band_spans_the_canvas_when_loaded_intact() -> void:
	var band := _add_band(false)
	assert_eq(band.size.x, get_viewport().get_visible_rect().size.x,
			"a band as authored fills the canvas width")


func test_band_spans_the_canvas_when_its_anchors_arrive_zeroed() -> void:
	var band := _add_band(true)
	assert_eq(band.size.x, get_viewport().get_visible_rect().size.x,
			"an export-damaged band re-asserts its own full width in _ready")


func test_a_zeroed_band_still_centres_its_text() -> void:
	var band := _add_band(true)
	band.play(AnnouncementRequest.make("YOUR TURN", "", AnnouncementRequest.Style.PHASE))
	await get_tree().create_timer(0.75).timeout
	var label: Label = band.get_node("Label")
	var centre: float = band.size.x * 0.5
	assert_almost_eq(label.position.x + label.size.x * 0.5, centre, Banner.DRIFT_OFFSET,
			"the text holds within a drift's reach of centre, not off the left edge")
