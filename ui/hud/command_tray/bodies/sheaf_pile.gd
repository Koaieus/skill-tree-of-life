@tool
class_name SheafPile
extends Control

## A stockpile drawn as sheaf tiers — singles, then tied bundles, then sheaves,
## then `+` — so the pile's size reads from its shape. Fed numbers only by its
## host; everything is one [method _draw] on this canvas item (no child per
## arrow), a few primitives per mark.

## Sentinel tier in [method marks]: the pile outgrew what the marks can show.
const PLUS := -1

@export var count: int = 0:
	set(v):
		count = maxi(v, 0)
		queue_redraw()
@export var tint: Color = Color.WHITE:
	set(v):
		tint = v
		queue_redraw()
## Value of one mark per tier, ascending; tier 0 is a single arrow.
@export var tier_sizes: PackedInt32Array = [1, 5, 25]:
	set(v):
		tier_sizes = v
		queue_redraw()
## Marks drawn before the pile collapses to `+`.
@export_range(1, 12) var max_marks: int = 5:
	set(v):
		max_marks = v
		queue_redraw()
## Horizontal pitch between marks, px.
@export_range(4.0, 32.0) var mark_spacing: float = 11.0:
	set(v):
		mark_spacing = v
		queue_redraw()
@export_range(0.5, 4.0) var line_px: float = 1.5:
	set(v):
		line_px = v
		queue_redraw()


## The tier index per mark, largest first. Greedy from the top tier and capped at
## [param max_marks], so the marks' summed value never exceeds [param count]; past
## [code]max_marks × top tier[/code] it is that many top-tier marks closed by
## [constant PLUS]. Assumes [param tier_sizes] ascending and positive.
static func marks(count: int, tier_sizes: PackedInt32Array, max_marks: int) -> Array[int]:
	var out: Array[int] = []
	if count <= 0 or tier_sizes.is_empty() or max_marks <= 0:
		return out
	var top := tier_sizes.size() - 1
	if count > max_marks * tier_sizes[top]:
		for i in max_marks:
			out.append(top)
		out.append(PLUS)
		return out
	var rest := count
	for t in range(top, -1, -1):
		while rest >= tier_sizes[t] and out.size() < max_marks:
			out.append(t)
			rest -= tier_sizes[t]
	return out


func _draw() -> void:
	var m := marks(count, tier_sizes, max_marks)
	var h := size.y
	for i in m.size():
		var x := mark_spacing * (i + 0.5)
		if m[i] == PLUS:
			_draw_plus(Vector2(x, h * 0.5))
		else:
			_draw_mark(x, h, m[i])


## Tier t fans `2t + 1` shafts (capped) and ties them with `t` bands: one
## multiline + one tip polyline + one tie multiline per mark.
func _draw_mark(x: float, h: float, tier: int) -> void:
	var shafts := mini(2 * tier + 1, 5)
	var spread := mark_spacing * 0.18 * tier
	var top := h * 0.08
	var bottom := h * 0.95
	var segs := PackedVector2Array()
	for s in shafts:
		var k := 0.0 if shafts == 1 else (float(s) / (shafts - 1) - 0.5) * 2.0
		segs.append(Vector2(x + k * spread * 0.4, bottom))
		segs.append(Vector2(x + k * spread, top))
	draw_multiline(segs, tint, line_px)
	var tip := mark_spacing * 0.22
	draw_polyline(PackedVector2Array([Vector2(x - tip, top + tip), Vector2(x, top - tip * 0.3), Vector2(x + tip, top + tip)]), tint, line_px)
	if tier == 0:
		return
	var ties := PackedVector2Array()
	for b in tier:
		var y := lerpf(h * 0.55, h * 0.75, 0.0 if tier == 1 else float(b) / (tier - 1))
		var half := spread * 0.7 + line_px
		ties.append(Vector2(x - half, y))
		ties.append(Vector2(x + half, y))
	draw_multiline(ties, tint, line_px * 1.5)


func _draw_plus(c: Vector2) -> void:
	var r := mark_spacing * 0.35
	draw_multiline(PackedVector2Array([c - Vector2(r, 0), c + Vector2(r, 0), c - Vector2(0, r), c + Vector2(0, r)]), tint, line_px * 1.5)
