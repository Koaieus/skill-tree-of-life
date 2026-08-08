extends GutTest

## AnnouncementLayer coalescing (#135, extended by #317).
##
## #135 merged a SAME-FRAME burst by matching against the queue's tail. #317
## paced those levels apart — one per XP-bar fill — which put each new request
## a second or more behind the one already playing, and a playing request has
## been popped off the queue. Without merging into it too, a routine 3-level
## kill queues three ~2.2s banners narrating a bar that finished long ago.

const _LAYER_SCENE := preload("res://ui/announcement_layer/announcement_layer.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _layer: AnnouncementLayer
var _entity: Entity


func before_each() -> void:
	_layer = _LAYER_SCENE.instantiate() as AnnouncementLayer
	add_child_autofree(_layer)
	_entity = Entity.new()
	autofree(_entity)
	_entity.display_name = "Leveller"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	await get_tree().process_frame


func _level_up(level: int) -> LevelUpAnnouncementRequest:
	return LevelUpAnnouncementRequest.make_for_level_up(_entity, 1, level)


func _playing() -> AnnouncementRequest:
	return _layer._current_by_kind.get(AnnouncementRequest.Kind.TITLE)


func _queued() -> Array:
	return _layer._queue_by_kind.get(AnnouncementRequest.Kind.TITLE)


func test_same_frame_burst_still_merges_in_the_queue() -> void:
	_layer.enqueue(_level_up(2))
	_layer.enqueue(_level_up(3))
	assert_eq(_queued().size(), 1, "merged before the deferred pump ran")
	assert_eq((_queued()[0] as LevelUpAnnouncementRequest).new_level, 3)


func test_a_level_up_absorbs_into_the_one_already_playing() -> void:
	_layer.enqueue(_level_up(2))
	await get_tree().process_frame  # pump: it's now playing, off the queue
	assert_not_null(_playing(), "first banner is up")
	assert_true(_queued().is_empty(), "and no longer queued")

	_layer.enqueue(_level_up(3))
	assert_true(_queued().is_empty(), "the second level did NOT queue a second banner")
	var live := _playing() as LevelUpAnnouncementRequest
	assert_eq(live.stack_count, 2, "it stamped ×2 on the live one instead")
	assert_eq(live.new_level, 3, "and re-read its sub-line")
	assert_eq(live.sub_text, "+2 Skill Points — Level 3")


func test_a_different_entity_does_not_absorb() -> void:
	_layer.enqueue(_level_up(2))
	await get_tree().process_frame
	var other := Entity.new()
	autofree(other)
	other.display_name = "Someone Else"
	other.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_layer.enqueue(LevelUpAnnouncementRequest.make_for_level_up(other, 1, 2))
	assert_eq(_queued().size(), 1, "coalescing is keyed by entity, not by kind")


## The playing-request merge must not disturb the running band: `amend` refreshes
## text and re-stamps the badge, but the banner keeps its own timeline and still
## reports `finished` exactly once.
func test_amending_does_not_restart_or_double_finish_the_band() -> void:
	var band: TitleBand = _layer._bands.get(AnnouncementRequest.Kind.TITLE)
	# Lambdas capture locals by value — count into a reference type.
	var finishes: Array[int] = []
	band.finished.connect(func(): finishes.append(1))
	_layer.enqueue(_level_up(2))
	await get_tree().process_frame
	var before := _playing()
	_layer.enqueue(_level_up(3))
	assert_true(finishes.is_empty(), "still playing, not restarted into completion")
	assert_same(before, _playing(), "the very same request object is still on screen")
