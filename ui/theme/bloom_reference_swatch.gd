@tool
extends PanelContainer
## A small, reusable bloom reference swatch — a row of test patches at rising
## EV tiers (default 0 through +4), meant to be dropped into the corner of any
## world SubViewport as a "slap it in and forget it" instrument. Two jobs:
##
## 1. **Proof.** If the patches at the higher tiers visibly glow, the hosting
##    viewport's glow pass is actually running — the same silent-failure risk
##    `addons/bloom_sandbox/bloom_sandbox_panel.gd` documents (wrong renderer,
##    `use_hdr_2d` off, an unregistered `WorldEnvironment`, an 8-bit render
##    target) all read identically here: patches that just sit there, flat.
## 2. **Scale.** Because every patch is at a known, named EV stop, it also
##    works as a comparison ruler — "does the effect I'm actually tuning read
##    hotter or cooler than the +2 patch" is a much steadier question than
##    eyeballing raw brightness.
##
## CRITICAL: this only tells the truth inside a bloom-capable `SubViewport`
## (`ui/theme/bloom_viewport.tscn` — `own_world_3d` + `use_hdr_2d` + a
## `WorldEnvironment`). Dropped into an ordinary outer `Control` tree (a
## panel's sidebar, a plain HUD layer) it renders unglowed flat squares and
## proves the exact opposite of what it's for. Per `.claude/rules/hdr-color.md`,
## every patch colour is `Emissive.at()`-derived — never a hand-picked float.
##
## Deliberately NOT the bloom sandbox's own reference chart
## (`addons/bloom_sandbox/bloom_sandbox_panel.gd`'s `_build_chart` /
## `_sample_row` / `_sample`): that chart is a full diagnostic surface —
## multiple backdrop bands, shape-coverage rows, an archetype-equalization
## comparison, all wired to the live-tuning sliders and picker in the same
## panel. This swatch is the opposite: small, static, host-agnostic, with no
## dependency on anything but `Emissive`. If the two ever want to share code,
## the shared unit is `Emissive.neutral(stop)` — already how both compute a
## patch colour — not the chart-building machinery itself.

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

const _LABEL_COLOR := Color(0.55, 0.6, 0.65)

var _row: HBoxContainer


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

	if _row != null:
		_row.queue_free()
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 3)
	add_child(_row)

	for stop in tiers:
		_row.add_child(_patch(stop))


func _patch(stop: float) -> VBoxContainer:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 1)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(patch_size, patch_size)
	swatch.color = Emissive.neutral(stop)
	cell.add_child(swatch)

	var label := Label.new()
	label.text = "%+.0f" % stop
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", _LABEL_COLOR)
	label.add_theme_font_size_override("font_size", 8)
	cell.add_child(label)

	return cell
