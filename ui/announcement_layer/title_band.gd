@tool
class_name TitleBand
extends AnnouncementBand

## Center-screen TITLE variant: wraps a main + sub [Banner] pair (today's
## "YOUR TURN" / "LEVEL UP" treatment) behind the single [AnnouncementBand]
## contract — the main/sub pairing is this variant's own implementation
## detail, invisible to [AnnouncementLayer].

@onready var _main: Banner = %MainBanner
@onready var _sub: Banner = %SubBanner

## Inspector button: play a sample banner for live preview in the editor.
@export_tool_button("Preview") var _preview_button: Callable = _preview

var _main_done: bool = true
var _sub_done: bool = true


func _ready() -> void:
	_main.finished.connect(_on_main_finished)
	_sub.finished.connect(_on_sub_finished)


func play(request: AnnouncementRequest) -> void:
	_main_done = request.main_text.is_empty()
	_sub_done = request.sub_text.is_empty()
	if not _main_done:
		_main.play(request)
	if not _sub_done:
		_sub.play(request)
	if _main_done and _sub_done:
		# Both lines empty — nothing to play; report done immediately.
		finished.emit()


## Re-stamp both lines in place (#317) — a second level-up absorbed while this
## banner is still on screen updates the ×N badge and the "+N Skill Points —
## Level M" sub-line without the banner sliding out and back in.
func amend(request: AnnouncementRequest) -> void:
	if not _main_done:
		_main.amend(request)
	if not _sub_done:
		_sub.amend(request)


func _preview() -> void:
	var sample := AnnouncementRequest.make(
			"LEVEL UP", "+3 Skill Points — Level 8", AnnouncementRequest.Style.LEVEL_UP)
	sample.stack_count = 3
	play(sample)


func _on_main_finished() -> void:
	_main_done = true
	_maybe_finish()


func _on_sub_finished() -> void:
	_sub_done = true
	_maybe_finish()


func _maybe_finish() -> void:
	if _main_done and _sub_done:
		finished.emit()
