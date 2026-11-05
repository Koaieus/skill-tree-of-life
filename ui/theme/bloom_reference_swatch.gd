@tool
extends PanelContainer
## A small, reusable row of test patches at rising EV tiers (default 0 through +4) to
## drop into the corner of any world SubViewport: proof the viewport's glow pass runs,
## and a comparison ruler. Only truthful inside a bloom-capable SubViewport
## (`ui/theme/bloom_viewport.tscn`); every patch colour is `Emissive.at()`-derived.
## See docs/domain/hdr-color.md

## Side length of one patch, in pixels. Small by design — this is a corner
## instrument, not a diagnostic panel; the default (16) is deliberately close
## to unreadable-as-a-shape and legible only as "does this glow".
@export var patch_size: float = 16.0:
	set(v):
		patch_size = v
		_rebuild()

## The EV stops drawn, left to right. Default spans roughly 0 (`Emissive.INERT`)
## through +4 — one stop past `Emissive.PEAK` (+3), so the strip shows what
## "brighter than the loudest named tier" looks like too.
@export var tiers: Array[float] = [0.0, 1.0, 2.0, 3.0, 4.0]:
	set(v):
		tiers = v
		_rebuild()

## Own dark backing so the patches read against a known ground rather than
## whatever happens to be behind them — a bright host background would wash
## out exactly the low-tier patches the comparison depends on.
const _BACKDROP := Color(0.03, 0.035, 0.05, 0.92)

const _PATCH := preload("res://ui/theme/bloom_reference_patch.tscn")


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return

	var style := StyleBoxFlat.new()
	style.bg_color = _BACKDROP
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	add_theme_stylebox_override("panel", style)

	var row := %Row as HBoxContainer
	# remove_child first: a queued-free patch would linger in the row until
	# frame end, and every inspector edit lands here.
	for old in row.get_children():
		row.remove_child(old)
		old.queue_free()
	for stop in tiers:
		row.add_child(_patch(stop))


func _patch(stop: float) -> VBoxContainer:
	var cell := _PATCH.instantiate() as VBoxContainer
	var swatch := cell.get_node(^"%Swatch") as ColorRect
	swatch.custom_minimum_size = Vector2(patch_size, patch_size)
	swatch.color = Emissive.neutral(stop)
	(cell.get_node(^"%Label") as Label).text = "%+.0f" % stop

	return cell
