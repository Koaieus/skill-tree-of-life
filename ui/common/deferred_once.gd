class_name DeferredOnce
extends RefCounted

## Coalesces a burst of [method request]s inside one frame into ONE deferred
## call of the Callable fixed at construction (#910).
##
## Why a receiver-owned flag and not a Callable-identity dedupe: `bind()`ed
## and lambda Callables compare by identity in ways that muddied a previous
## attempt (owner, 2026-09-16). Fixing the Callable at construction makes
## bound-vs-unbound a non-question — one [DeferredOnce] is one unit of work.
## Different arguments are different work and not this util's job.
##
## Precedent: `VisionSystem._request_recompute` / `_recompute_deferred`; the
## seven hand-rolled `_pending` + `call_deferred` twins migrate onto this in
## #917.
##
## Typical use — a HUD panel that must rebuild at most once per frame however
## many signals fire inside one synchronous loop:
## [codeblock]
## var _rebuild := DeferredOnce.new(_rebuild_now)
## ...
## turn_manager.forecast_changed.connect(_rebuild.request)
## [/codeblock]

var _fn: Callable
var _queued: bool = false


func _init(fn: Callable) -> void:
	_fn = fn


## Schedule the Callable for the end of this frame, unless it already is.
func request() -> void:
	if _queued:
		return
	_queued = true
	_run.call_deferred()


## True between a [method request] and the deferred run it scheduled.
func is_queued() -> bool:
	return _queued


func _run() -> void:
	_queued = false
	if _fn.is_valid():
		_fn.call()
