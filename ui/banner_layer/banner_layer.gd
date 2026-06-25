@tool
class_name BannerLayer
extends CanvasLayer

## Full-viewport announcer that plays animated [Banner]s back-to-back from a
## FIFO queue. The scene houses one main band and one sub band ([code]%MainBanner[/code]
## / [code]%SubBanner[/code]); a single [BannerRequest] drives both in parallel
## (atomic display, e.g. "TURN STARTED / CONTRACTION PHASE").
##
## Public API ([method enqueue] / [method enqueue_now] / [method clear])
## is the only contract — call sites build a [BannerRequest] and submit it.
## Routing (which signal becomes which request) lives in [BannerDirector],
## not here.

@onready var _main: Banner = %MainBanner
@onready var _sub: Banner = %SubBanner

## Inspector button: queue a sample TURN STARTED / CONTRACTION PHASE for
## live preview in the editor.
@export_tool_button("Preview") var _preview_button: Callable = _preview

var _queue: Array[BannerRequest] = []
var _current: BannerRequest = null
var _main_done: bool = true
var _sub_done: bool = true

# Optional turn-state source for staleness checks. When set, requests carrying
# a `{entity, phase}` context get dropped on dequeue if the live state has
# already moved past them. See [method BannerRequest.make_for_phase].
var _turn_manager: TurnManager = null


func _ready() -> void:
	_main.finished.connect(_on_main_finished)
	_sub.finished.connect(_on_sub_finished)


## Hand in the TurnManager so the layer can drop stale phase banners. Optional;
## without this, all requests play in order regardless of their context.
func bind_turn_manager(tm: TurnManager) -> void:
	_turn_manager = tm


## Standard FIFO: append to the queue; if idle, kick off immediately.
## Dedups against the tail of the queue (same text + style) so rapid-fire
## identical enqueues collapse.
func enqueue(req: BannerRequest) -> void:
	if req == null:
		return
	if not _queue.is_empty() and _queue[-1].equivalent_to(req):
		return
	_queue.append(req)
	_pump()


## Preempt: drop pending queue, interrupt the running banner (if any),
## and play [param req] immediately. Use for high-priority events that
## shouldn't wait behind backlog.
func enqueue_now(req: BannerRequest) -> void:
	if req == null:
		return
	_queue.clear()
	_queue.append(req)
	_main_done = true
	_sub_done = true
	_current = null
	_pump()


## Drain pending queue without interrupting the currently playing banner.
func clear() -> void:
	_queue.clear()


func _preview() -> void:
	enqueue_now(BannerRequest.make(
			"TURN STARTED", "CONTRACTION PHASE", BannerRequest.Style.DEFAULT))


func _pump() -> void:
	if _current != null:
		return
	# Skip stale entries (e.g. phase banners for a turn that already ended)
	# before deciding to play anything.
	while not _queue.is_empty() and _should_skip(_queue[0]):
		_queue.pop_front()
	if _queue.is_empty():
		return
	_current = _queue.pop_front()
	_main_done = _current.main_text.is_empty()
	_sub_done = _current.sub_text.is_empty()
	if not _main_done:
		_main.play(_current.main_text, _current.style)
	if not _sub_done:
		_sub.play(_current.sub_text, _current.style)
	if _main_done and _sub_done:
		# Both empty — nothing to play; advance.
		_current = null
		_pump()


## True if `req`'s context says the live turn-state has moved past it
## (different entity is acting, or the announced phase is already over).
func _should_skip(req: BannerRequest) -> bool:
	if req == null or req.context.is_empty() or _turn_manager == null:
		return false
	var ctx_entity := req.context.get(&"entity") as Entity
	if ctx_entity != null and _turn_manager.current_entity != ctx_entity:
		return true
	if req.context.has(&"phase"):
		var ctx_phase: int = req.context[&"phase"]
		if int(_turn_manager.current_phase) > ctx_phase:
			return true
	return false


func _on_main_finished() -> void:
	_main_done = true
	_maybe_advance()


func _on_sub_finished() -> void:
	_sub_done = true
	_maybe_advance()


func _maybe_advance() -> void:
	if _main_done and _sub_done:
		_current = null
		_pump()
