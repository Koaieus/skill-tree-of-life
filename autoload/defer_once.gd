extends Node
class_name DeferOnceUtil

## Global "defer once per frame" helper.
## Usage:
##   DeferOnce.defer_once(Callable(target, "method_name"))

var _pending_methods: Dictionary = {}
var _flush_queued: bool = false

func defer_once(callable: Callable) -> void:
	if not _flush_queued:
		_flush_queued = true
		_flush.call_deferred()
		
	_pending_methods[callable] = true


func _flush() -> void:
	for callable in _pending_methods.keys():
		assert(callable.is_valid(), 'Invalid callable: %s' % callable)
		if callable.is_valid():
			callable.call()
		else:
			push_warning("DeferredOnce: Invalid callable skipped: ", callable)

	_pending_methods.clear()
	_flush_queued = false
