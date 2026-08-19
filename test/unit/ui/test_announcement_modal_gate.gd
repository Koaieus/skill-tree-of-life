extends GutTest

## AnnouncementLayer's modal-open gate (#486): a Tween-driven band keeps
## animating under the old `get_tree().paused` block, so a banner could render
## on top of a paused, dimmed picker modal. `set_modal_open(true)` blocks new
## dequeues without touching a band already mid-play; `set_modal_open(false)`
## re-pumps whatever queued up while blocked.

const _LAYER_SCENE := preload("res://ui/announcement_layer/announcement_layer.tscn")

var _layer: AnnouncementLayer


func before_each() -> void:
	_layer = _LAYER_SCENE.instantiate() as AnnouncementLayer
	add_child_autofree(_layer)
	await get_tree().process_frame


func _callout(text: String) -> AnnouncementRequest:
	return AnnouncementRequest.make(text, "", AnnouncementRequest.Style.DEFAULT,
			AnnouncementRequest.Kind.CALLOUT)


func _playing() -> AnnouncementRequest:
	return _layer._current_by_kind.get(AnnouncementRequest.Kind.CALLOUT)


func test_enqueue_while_modal_open_does_not_play() -> void:
	_layer.set_modal_open(true)
	_layer.enqueue(_callout("MELEE"))
	await get_tree().process_frame
	assert_null(_playing(), "blocked while a modal is open")


func test_closing_the_modal_pumps_the_queued_request() -> void:
	_layer.set_modal_open(true)
	_layer.enqueue(_callout("MELEE"))
	await get_tree().process_frame
	_layer.set_modal_open(false)
	assert_not_null(_playing(), "queued request plays as soon as the modal closes")


func test_a_band_already_playing_is_not_interrupted_by_the_modal_opening() -> void:
	_layer.enqueue(_callout("MELEE"))
	await get_tree().process_frame
	var before := _playing()
	assert_not_null(before, "playing before the modal opens")
	_layer.set_modal_open(true)
	assert_same(before, _playing(), "already-playing band is left alone, not cut off")
