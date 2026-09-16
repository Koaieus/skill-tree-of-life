extends GutTest

## #910 — [DeferredOnce]: a burst of `request()`s inside one frame lands as
## exactly ONE deferred call, and the flag re-arms afterwards.

var _calls: int = 0


func _count() -> void:
	_calls += 1


func test_fifty_requests_one_frame_one_call() -> void:
	var once := DeferredOnce.new(_count)
	for i in 50:
		once.request()
	assert_eq(_calls, 0, "nothing runs synchronously")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_calls, 1, "the burst coalesces into one call")


func test_rearms_after_the_deferred_call() -> void:
	var once := DeferredOnce.new(_count)
	once.request()
	await get_tree().process_frame
	await get_tree().process_frame
	once.request()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_calls, 2, "a request in a later frame runs again")
