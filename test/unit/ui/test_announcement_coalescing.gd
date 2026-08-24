extends GutTest

## AnnouncementLayer coalescing (#135, extended by #317).
##
## #135 merged a SAME-FRAME burst by matching against the queue's tail. #317
## paced repeats apart — a beat or more between them — which puts each new
## request behind the one already playing, and a playing request has been popped
## off the queue. Without merging into it too, three paced repeats queue three
## ~2.2s banners narrating something the screen finished saying long ago.
##
## The level-up cascade was the original driver and no longer uses this layer at
## all (#320 moved it onto the XP bar, where the queue actually lives). The
## MACHINERY stays, and is what these tests pin: the entity-keyed request below
## is a fixture standing in for the next announcement that repeats — ENEMY SLAIN
## is the one #320 has queued up — not a copy of anything in production.


## Test-local stand-in for a repeating, entity-keyed announcement: coalesces on
## the entity rather than on exact text, and folds the newer request's number
## into the line already on screen.
class _RepeatingRequest extends AnnouncementRequest:
	var entity: Entity
	var count: int = 1

	func coalesce_key() -> Variant:
		return ["repeat", entity]

	func absorb(other: AnnouncementRequest) -> void:
		stack_count += other.stack_count
		var r := other as _RepeatingRequest
		if r != null:
			count = r.count
		sub_text = "count %d" % count

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


func _repeat(n: int, ent: Entity = null) -> _RepeatingRequest:
	var r := _RepeatingRequest.new()
	r.entity = _entity if ent == null else ent
	r.count = n
	r.kind = AnnouncementRequest.Kind.TITLE
	r.main_text = "REPEAT"
	r.sub_text = "count %d" % n
	r.context = {&"entity": r.entity}
	return r


func _playing() -> AnnouncementRequest:
	return _layer._current_by_kind.get(AnnouncementRequest.Kind.TITLE)


func _queued() -> Array:
	return _layer._queue_by_kind.get(AnnouncementRequest.Kind.TITLE)


func test_same_frame_burst_still_merges_in_the_queue() -> void:
	_layer.enqueue(_repeat(2))
	_layer.enqueue(_repeat(3))
	assert_eq(_queued().size(), 1, "merged before the deferred pump ran")
	assert_eq((_queued()[0] as _RepeatingRequest).count, 3)


func test_a_repeat_absorbs_into_the_one_already_playing() -> void:
	_layer.enqueue(_repeat(2))
	await get_tree().process_frame  # pump: it's now playing, off the queue
	assert_not_null(_playing(), "first banner is up")
	assert_true(_queued().is_empty(), "and no longer queued")

	_layer.enqueue(_repeat(3))
	assert_true(_queued().is_empty(), "the repeat did NOT queue a second banner")
	var live := _playing() as _RepeatingRequest
	assert_eq(live.stack_count, 2, "it stamped ×2 on the live one instead")
	assert_eq(live.count, 3, "and re-read its sub-line")
	assert_eq(live.sub_text, "count 3")


func test_a_different_entity_does_not_absorb() -> void:
	_layer.enqueue(_repeat(2))
	await get_tree().process_frame
	var other := Entity.new()
	autofree(other)
	other.display_name = "Someone Else"
	other.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_layer.enqueue(_repeat(2, other))
	assert_eq(_queued().size(), 1, "coalescing is keyed by entity, not by kind")


## The playing-request merge must not disturb the running band: `amend` refreshes
## text and re-stamps the badge, but the banner keeps its own timeline and still
## reports `finished` exactly once.
func test_amending_does_not_restart_or_double_finish_the_band() -> void:
	var band: TitleBand = _layer._bands.get(AnnouncementRequest.Kind.TITLE)
	# Lambdas capture locals by value — count into a reference type.
	var finishes: Array[int] = []
	band.finished.connect(func(): finishes.append(1))
	_layer.enqueue(_repeat(2))
	await get_tree().process_frame
	var before := _playing()
	_layer.enqueue(_repeat(3))
	assert_true(finishes.is_empty(), "still playing, not restarted into completion")
	assert_same(before, _playing(), "the very same request object is still on screen")
