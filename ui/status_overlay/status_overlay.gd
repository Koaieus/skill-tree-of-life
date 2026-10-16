@tool
class_name StatusOverlay
extends Control

## Every status readout on a bar: the projected-damage segment and the icon
## row, for ONE host's rows. Composed as a full-rect child of the bar it
## annotates; the bar owns the wiring.
##
## [b]Host.[/b] [method bind] takes a [NodeCombat] or an [EntityCombat] (both
## answer `get_statuses()` and `projected_status_damage()`) plus the signal that
## announces a row change ([signal SkillNode.statuses_changed] /
## [signal Entity.statuses_changed]). A node bar binds its node, a core bar the
## entity — two overlays, never merged.
##
## [b]Fill.[/b] The bar pushes the fill it is DRAWING through [method set_fill]
## (its animated `value`, not the pool), so the band stays glued to the fill tip
## while a damage tween runs.
##
## [b]Model, then draw.[/b] [method refresh] rebuilds [member segments] and
## [member icons] from the live rows; `_draw` only paints them. A consumer (or a
## later readout) adds segments to the model, never draws status on a bar
## outside this scene. Zero rows → hidden, so a clean node costs no `_draw`.
## Colour is the row identity's `tint`, unlifted; icons share their textures
## and tint through `modulate`, so the row batches.
##
## [b]Corruption layer[/b] (node hosts only: an entity row has no threshold).
## A [SandpileSpread] row of a [CorruptionStatus] at `N` stacks against the
## node's live `T` ([method SandpileSpread.threshold_of]) draws N blips above
## the icon row and N pending chunks back from the tip, worth exactly what a
## degree-loss pop deals ([method CorruptionStatus.burst_amount] at `N`).
## While critical (`N == T − 1`) a ghost chunk follows, worth the extra a
## landing stack's pop deals at `T`. `N` is drawn as read: a transient
## `N ≥ T` mid-settle is legal. `T` moves with no row change (a neighbour's
## owner, an incident edge or gate flip), so while a pile stands the overlay
## also listens to those. The pulse reads one global clock in `_draw`.

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
	ghost = Rect2()
	critical = false
	var rows := _rows()
	visible = not rows.is_empty()
	if rows.is_empty():
		set_process(false)
		return
	_build_segments(rows)
	_build_icons(rows)
	set_process(not blips.is_empty())
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _on_rows_changed() -> void:
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
