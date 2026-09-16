class_name DeferredOnce
extends RefCounted

## Coalesces a burst of `request()`s within one frame into ONE deferred call
## of the Callable fixed at construction (#910). Stub — see the test go red.

var _fn: Callable


func _init(fn: Callable) -> void:
	_fn = fn


func request() -> void:
	_fn.call_deferred()
