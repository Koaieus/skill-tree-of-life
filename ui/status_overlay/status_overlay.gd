@tool
class_name StatusOverlay
extends Control

## Every status readout on a bar: the projected-damage segment and the icon row,
## for ONE host's rows; a full-rect child of the bar it annotates. [method bind]
## takes a [NodeCombat] or [EntityCombat] plus its statuses-changed signal; the bar
## pushes its DRAWN fill via [method set_fill]. [method refresh] rebuilds the model
## and `_draw` only paints it. Node hosts add a corruption layer. One overlay
## draws one [enum Layer]: a bar's overlay the statuses, a skill node's own
## free-standing overlay the Catalyst crystals (outside the bar's fade).
## See docs/domain/hud-widgets.md

## One band of the projected-damage segment: one damaging row, stacked back
## from the fill tip in row order.
class Segment:
	var id: StringName
	var rect: Rect2
	var color: Color

## One icon of the row. `count` is the stack count, `-1` when the def's stacks
## do not matter ([member StatusDef.display_max] ≤ 1).
class IconEntry:
	var id: StringName
	var texture: Texture2D
	var count: int = -1
	var rect: Rect2

## What one overlay draws. STATUS: the segment, icon row and corruption, over
## a bar. CATALYST: one crystal per Catalyst stack and the conversion pulse,
## on a skill node's own overlay; it never fades with a bar, so a full-HP or
## unallocated carrier shows its crystals.
enum Layer { STATUS, CATALYST }

@export var layer: Layer = Layer.STATUS:
	set(v):
		layer = v
		refresh()
## Edge of one icon, px. Tentative, easy to change.
@export_range(4.0, 32.0, 1.0) var icon_size: float = 10.0:
	set(v):
		icon_size = v
		refresh()
## Gap between icons, and between the row and the bar, px. Tentative.
@export_range(0.0, 8.0, 0.5) var icon_gap: float = 2.0:
	set(v):
		icon_gap = v
		refresh()

## Corruption blip edge, px. Tentative, easy to change.
@export_range(1.0, 16.0, 0.5) var blip_size: float = 4.0:
	set(v):
		blip_size = v
		refresh()
## Gap between blips, and between the blip row and the icon row, px. Tentative.
@export_range(0.0, 8.0, 0.5) var blip_gap: float = 2.0:
	set(v):
		blip_gap = v
		refresh()
## Seconds per pulse of the pending chunks at rest. Tentative, easy to change.
@export_range(0.1, 5.0, 0.05) var pulse_period: float = 1.2:
	set(v):
		pulse_period = v
		queue_redraw()
## Seconds per pulse while critical. Tentative, easy to change.
@export_range(0.1, 5.0, 0.05) var critical_pulse_period: float = 0.45:
	set(v):
		critical_pulse_period = v
		queue_redraw()
## Crystal edge (width), px: one violet crystal per Catalyst stack, standing
## on the icon row. Tentative, easy to change.
@export_range(2.0, 16.0, 0.5) var crystal_size: float = 5.0:
	set(v):
		crystal_size = v
		refresh()
## Most crystals drawn for one Catalyst row; more stacks show as this many.
## Tentative, easy to change.
@export_range(1, 12, 1) var crystal_cap: int = 6:
	set(v):
		crystal_cap = v
		refresh()
## Seconds a conversion pulse takes to fade. Tentative, easy to change.
@export_range(0.05, 2.0, 0.05) var conversion_pulse_seconds: float = 0.5
## How much a pulsing crystal swells at the pulse's start (1 = not at all).
## Tentative, easy to change.
@export_range(1.0, 3.0, 0.05) var conversion_pulse_swell: float = 1.6
## How far the corruption tint darkens for a pending chunk. Tentative.
@export_range(0.0, 1.0, 0.05) var chunk_darken: float = 0.45:
	set(v):
		chunk_darken = v
		queue_redraw()
## The hotter named tier critical chunks and blips peak at.
@export var critical_tier: Emissive.Tier = Emissive.Tier.ALERT:
	set(v):
		critical_tier = v
		queue_redraw()

## The model `_draw` paints. Read-only for callers.
var segments: Array[Segment] = []
var icons: Array[IconEntry] = []
## The corruption layer (node hosts only): one pending chunk per stack, stacked
## back from the tip after the bands; the ghost (N+1)th chunk while critical
## (empty otherwise); one blip per stack above the icon row.
var chunks: Array[Rect2] = []
var ghost: Rect2 = Rect2()
var blips: Array[Rect2] = []
## The Catalyst layer (node hosts, [enum Layer] CATALYST only): one crystal
## per stack, and the tint its conversion pulse flashes in.
var crystals: Array[Rect2] = []
## The last non-empty crystal row: a take spends the row before its cue lands,
## so the pulse flashes these.
var _last_crystals: Array[Rect2] = []
var _crystal_tint: Color = Color.WHITE
var _pulse_left: float = 0.0
## The conversion pulse's colour: the landing element's tint ([method _on_catalyst_converted]).
var _pulse_tint: Color = Color.WHITE
## The crystals the running pulse flashes: the row as last drawn before the take.
var pulse_crystals: Array[Rect2] = []
## `N == T − 1`: one more stack, or one lost degree, cashes the chunks in.
var critical: bool = false

var _host: Object = null
var _fill_value: float = 0.0
var _fill_max: float = 0.0
var _subs := SubBag.new()
## Degree listeners, live only while a corruption pile stands on the node.
var _degree_subs := SubBag.new()
var _corruption_tint: Color = Color.WHITE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		refresh()


## Point at [param host]'s rows (null detaches). [param changed] fires on every
## apply / tick / remove of those rows.
func bind(host: Object, changed: Signal = Signal()) -> void:
	_subs.clear()
	_host = host
	_last_crystals.clear()
	if layer == Layer.CATALYST and _host is NodeCombat and (_host as NodeCombat).real() != null:
		_subs.on((_host as NodeCombat).real().catalyst_converted, _on_catalyst_converted)
	if _host != null and not changed.is_null():
		_subs.on(changed, _on_rows_changed)
	_on_rows_changed()


## The fill the hosting bar is drawing right now, in its own units.
func set_fill(fill_value: float, fill_max: float) -> void:
	_fill_value = fill_value
	_fill_max = fill_max
	refresh()


func has_rows() -> bool:
	return not _rows().is_empty()


## Rebuild the model from the live rows and repaint.
func refresh() -> void:
	segments.clear()
	icons.clear()
	chunks.clear()
	blips.clear()
	crystals.clear()
	ghost = Rect2()
	critical = false
	var rows := _rows()
	if layer == Layer.CATALYST:
		_build_crystals(rows)
		visible = not crystals.is_empty() or is_pulsing()
		set_process(is_pulsing())
		queue_redraw()
		return
	visible = not rows.is_empty()
	if rows.is_empty():
		set_process(false)
		queue_redraw()
		return
	_build_segments(rows)
	_build_icons(rows)
	set_process(not blips.is_empty())
	queue_redraw()


func _process(delta: float) -> void:
	if _pulse_left > 0.0:
		_pulse_left = maxf(_pulse_left - delta, 0.0)
		if _pulse_left == 0.0:
			refresh()
			return
	queue_redraw()


## The cue, heard on this overlay's own node: flash the crystals the take
## spent in [method pulse_tint] of [param converted] (a running pulse's tint,
## else the crystal tint, when it names no element).
func _on_catalyst_converted(converted: Dictionary = {}) -> void:
	_pulse_tint = pulse_tint(converted, _pulse_tint if is_pulsing() else _crystal_tint)
	pulse_crystals = crystals.duplicate() if not crystals.is_empty() else _last_crystals.duplicate()
	if pulse_crystals.is_empty():
		pulse_crystals.append(Rect2(0.0, 0.0, crystal_size, crystal_size * 1.6))
	_pulse_left = conversion_pulse_seconds
	visible = true
	set_process(true)
	queue_redraw()


func is_pulsing() -> bool:
	return _pulse_left > 0.0


## The pulse's colour for a conversion: the tint of the element [param converted]
## made the most stacks of, the first named on a tie (tentative); [param fallback]
## when it names no known element.
static func pulse_tint(converted: Dictionary, fallback: Color) -> Color:
	var tint := fallback
	var most := 0
	for id: Variant in converted:
		var e := ElementRoster.shared().by_id(id)
		if int(converted[id]) > most and e != null and e.identity != null:
			most = int(converted[id])
			tint = e.identity.tint
	return tint


## One crystal per stack of the node's Catalyst row, left to right from the
## overlay's top-left; clamped at [member crystal_cap].
func _build_crystals(rows: Array[NodeStatus]) -> void:
	if not (_host is NodeCombat):
		return
	for row in rows:
		if not (row.def is CatalystStatus) or row.power <= 0.0:
			continue
		_crystal_tint = row.def.tint
		for i in mini(roundi(row.power), crystal_cap):
			crystals.append(Rect2(i * (crystal_size + icon_gap), 0.0, crystal_size, crystal_size * 1.6))
		_last_crystals = crystals.duplicate()
		return


func _on_rows_changed() -> void:
	if layer == Layer.STATUS:
		_rewire_degree()
	refresh()


## Re-subscribe the degree listeners: the node's own and each neighbour's
## `owner_changed`, and the graph's edge signals (a gate flip adds / removes
## an edge). Only while a corruption pile stands; cleared at N = 0.
func _rewire_degree() -> void:
	_degree_subs.clear()
	var node := _host as NodeCombat if _host != null and is_instance_valid(_host) else null
	if node == null or _corruption_row(_rows()) == null:
		return
	var real := node.real()
	if real == null:
		return
	_degree_subs.on(real.owner_changed, _on_rows_changed)
	var owner_slice := node.owner()
	var mirror: GraphMirror = owner_slice.mirror() if owner_slice != null else null
	if mirror == null or mirror.graph == null:
		return
	_degree_subs.on(mirror.graph.edge_added, _on_edge_changed)
	_degree_subs.on(mirror.graph.edge_removed, _on_edge_changed)
	for m in mirror.graph.get_neighbours(real):
		_degree_subs.on(m.owner_changed, refresh)


func _on_edge_changed(edge: Edge) -> void:
	var node := _host as NodeCombat if _host != null and is_instance_valid(_host) else null
	if node == null or edge == null:
		return
	var real := node.real()
	if edge.from == real or edge.to == real:
		_on_rows_changed()


## The node's corruption pile row, or null (entity hosts have no `T`).
func _corruption_row(rows: Array[NodeStatus]) -> NodeStatus:
	if not (_host is NodeCombat):
		return null
	for row in rows:
		if row.def is CorruptionStatus and row.def.spread is SandpileSpread and row.power > 0.0:
			return row
	return null


func _rows() -> Array[NodeStatus]:
	if _host == null or not is_instance_valid(_host):
		return []
	return _host.get_statuses()


func _build_segments(rows: Array[NodeStatus]) -> void:
	var tip := clampf(_fill_value / _fill_max, 0.0, 1.0) * size.x if _fill_max > 0.0 else 0.0
	var pile := _corruption_row(rows)
	for row in rows:
		if row == pile:
			tip = _build_corruption(row, tip)
			continue
		var dmg: float = row.def.projected_damage(_host, row.power)
		if dmg <= 0.0 or tip <= 0.0:
			continue
		var w := minf(dmg / _fill_max * size.x, tip)
		var s := Segment.new()
		s.id = row.def.id
		s.color = row.def.tint
		s.rect = Rect2(tip - w, 0.0, w, size.y)
		segments.append(s)
		tip -= w


## Blips, chunks and the ghost for [param row]; returns the tip left over.
func _build_corruption(row: NodeStatus, tip: float) -> float:
	var def := row.def as CorruptionStatus
	var n := roundi(row.power)
	if n <= 0:
		return tip
	var t := (def.spread as SandpileSpread).threshold_of(_host)
	critical = n == t - 1
	_corruption_tint = def.tint
	var y := -icon_size - icon_gap - blip_gap - blip_size
	for i in n:
		blips.append(Rect2(i * (blip_size + blip_gap), y, blip_size, blip_size))
	if _fill_max <= 0.0 or tip <= 0.0:
		return tip
	var px := size.x / _fill_max
	var solid := def.burst_amount(_host, 1, n)
	var each := solid / float(n) * px
	for i in n:
		var w := minf(each, tip)
		if w <= 0.0:
			return tip
		chunks.append(Rect2(tip - w, 0.0, w, size.y))
		tip -= w
	if critical:
		var w := minf((def.burst_amount(_host, 1, t) - solid) * px, tip)
		if w > 0.0:
			ghost = Rect2(tip - w, 0.0, w, size.y)
			tip -= w
	return tip


func _build_icons(rows: Array[NodeStatus]) -> void:
	var x := 0.0
	var y := -icon_size - icon_gap
	for row in rows:
		var tex: Texture2D = row.def.icon
		if tex == null:
			continue
		var e := IconEntry.new()
		e.id = row.def.id
		e.texture = tex
		e.count = row.power if row.def.display_max > 1.0 else -1
		e.rect = Rect2(x, y, icon_size, icon_size)
		icons.append(e)
		x += icon_size + icon_gap


func _draw() -> void:
	for s in segments:
		draw_rect(s.rect, s.color)
	if not blips.is_empty():
		_draw_corruption()
	if layer == Layer.CATALYST:
		_draw_catalyst()
		return
	var font := ThemeDB.fallback_font
	var font_size := maxi(int(icon_size * 0.8), 6)
	for e in icons:
		draw_texture_rect(e.texture, e.rect, false)
		if e.count >= 0:
			draw_string_outline(font, e.rect.end + Vector2(-font_size * 0.5, 0.0), str(e.count),
					HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, Color.BLACK)
			draw_string(font, e.rect.end + Vector2(-font_size * 0.5, 0.0), str(e.count),
					HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


## One shared phase: every overlay reads the same clock, so hundreds pulse in
## step with no tween each.
func _draw_corruption() -> void:
	var period := critical_pulse_period if critical else pulse_period
	var now := float(Time.get_ticks_msec()) / 1000.0
	var pulse := 0.5 + 0.5 * sin(TAU * now / maxf(period, 0.01))
	var dark := _corruption_tint.darkened(chunk_darken)
	var hot := Emissive.at(_corruption_tint, Emissive.stops(critical_tier)) if critical else _corruption_tint
	var chunk_color := dark.lerp(hot, pulse * (1.0 if critical else 0.5))
	for r in chunks:
		draw_rect(r, chunk_color)
	if ghost.has_area():
		# Alternates between the health fill showing through and the dark chunk.
		var g := dark
		g.a = pulse
		draw_rect(ghost, g)
	for i in blips.size():
		var last := i == blips.size() - 1
		draw_rect(blips[i], hot.lerp(dark, 1.0 - pulse) if critical and last else _corruption_tint)


func _draw_catalyst() -> void:
	for r in crystals:
		_draw_crystal(r, _crystal_tint)
	if not is_pulsing():
		return
	# The spent crystals flash in the landing element's tint, swelling and fading.
	var t := _pulse_left / maxf(conversion_pulse_seconds, 0.01)
	var tint := _pulse_tint.lerp(Color.WHITE, 0.35 * t)
	tint.a = t
	var grow := lerpf(1.0, conversion_pulse_swell, t)
	for r in pulse_crystals:
		_draw_crystal(r.grow_individual(
				r.size.x * (grow - 1.0) * 0.5, r.size.y * (grow - 1.0) * 0.5,
				r.size.x * (grow - 1.0) * 0.5, r.size.y * (grow - 1.0) * 0.5), tint)


## A faceted crystal filling [param r] in [param tint]: a lit left half, a darker right.
func _draw_crystal(r: Rect2, tint: Color) -> void:
	var mid := r.position.x + r.size.x * 0.5
	var shoulder := r.position.y + r.size.y * 0.3
	var apex := Vector2(mid, r.position.y)
	var base := Vector2(mid, r.end.y)
	var left := Vector2(r.position.x, shoulder)
	var right := Vector2(r.end.x, shoulder)
	draw_colored_polygon(PackedVector2Array([apex, right, Vector2(r.end.x, r.end.y - r.size.y * 0.2), base,
			Vector2(r.position.x, r.end.y - r.size.y * 0.2), left]), tint.darkened(0.35))
	draw_colored_polygon(PackedVector2Array([apex, left, Vector2(r.position.x, r.end.y - r.size.y * 0.2), base]),
			tint)

