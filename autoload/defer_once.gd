extends Node
class_name DeferOnceUtil

## Global "defer once per frame" helper.
## Usage:
##   DeferOnce.defer_once(Callable(target, "method_name"))

static var _pending_methods: Dictionary = {}
static var _flush_queued: bool = false

static func defer_once(callable: Callable) -> void:
	if not _flush_queued:
		_flush_queued = true
		_flush.call_deferred()
		
	_pending_methods[callable] = true


static func _flush() -> void:
	for callable in _pending_methods.keys():
		if callable.is_valid():
			callable.call()
		else:
			push_warning("DeferredOnce: Invalid callable skipped: ", callable)

	_pending_methods.clear()
	_flush_queued = false
