@tool
class_name TerrainBars
extends Node2D

## The terrain bars south of a skill node (#1796; `docs/domain/skillnode-visuals.md`
## § Terrain bars). One bar for heat/cold — red or blue by the sign of t — and
## one for Charge, with sparkles. A bar is a frame of blocks, one block holding
## `degree` stacks: the inert blocks up to T, the primed ones up to the cap,
## then the overflow as a short tail past the frame that flickers and fades.
## Under each bar, the element's one label ([method label_for] — the one name
## read; the tooltip row calls it too, and nothing re-derives it).
##
## Shown while hovered or pinned, on owned and unowned nodes alike, and briefly
## when a world turn moved this node's terrain ([method flash], the spread cue).
## Subscribed to [signal SkillNode.terrain_changed] only while shown ([SubBag]:
## [method SubBag.now] paints first, [method SubBag.clear] on hide). Draws
## everything itself in [method _draw]; never joins [StatusOverlay].

## The pure layout of one bar, in blocks.
class Layout:
	## The frame: the cap in blocks (k × t_per_degree).
	var frame_blocks: int = 0
	## The first blocks, up to T (t_per_degree).
	var inert_blocks: int = 0
	## count / degree, clamped to the frame — a leaf counts stacks exactly.
	var fill_blocks: float = 0.0
	## ceil((count − cap) / degree), capped at the tail's length.
	var overflow_blocks: int = 0


## One bar to draw: the element it shows and everything read off the node.
class Bar:
	var element: Element = null
	var count: int = 0
	var degree: int = 0
	## The bar's fill: the element's tint (red for Heat, blue for Cold).
	var color: Color = Color.WHITE
	## The label's colour and icon: the shown band's [Identity], else the element's.
	var label_color: Color = Color.WHITE
	var icon: Texture2D = null
	var label: String = ""
	var layout: Layout = null


const _FADE_IN_S := 0.15
const _FADE_OUT_S := 0.4
const _FRAME := Color(1, 1, 1, 0.55)
const _EMPTY_INERT := Color(0, 0, 0, 0.55)
const _EMPTY_PRIMED := Color(0.12, 0.12, 0.14, 0.7)

## Block edge along the bar, px. Tentative.
@export_range(2.0, 24.0, 0.5) var block_size: float = 6.0:
	set(value):
		block_size = value
		queue_redraw()
## Space between blocks and between a bar and its label, px. Tentative.
@export_range(0.0, 8.0, 0.5) var gap: float = 1.0:
	set(value):
		gap = value
		queue_redraw()
## Bar thickness, px. Tentative.
@export_range(2.0, 24.0, 0.5) var bar_height: float = 5.0:
	set(value):
		bar_height = value
		queue_redraw()
## The first bar's top edge below the node centre, px (the health bar sits
## north). Tentative.
@export_range(0.0, 200.0, 1.0) var south_offset: float = 46.0:
	set(value):
		south_offset = value
		queue_redraw()
## The label's font size under each bar, px. Tentative.
@export_range(6, 24, 1) var label_size: int = 9:
	set(value):
		label_size = value
		queue_redraw()
## The overflow tail past the frame, in blocks. Tentative.
@export_range(0, 8, 1) var max_overflow_blocks: int = 3:
	set(value):
		max_overflow_blocks = value
		_refresh()
## One flicker of the overflow tail, seconds. Tentative; tune in the sandbox tab.
@export_range(0.05, 4.0, 0.01) var flicker_period: float = 0.4
## How long the spread cue holds the bars up after fading in, seconds. Tentative.
@export_range(0.0, 5.0, 0.05) var flash_hold_s: float = 0.8

## Bench pin ([member SkillNode.pin_health_bar]): shown regardless of hover.
var pinned: bool = false:
	set(value):
		if pinned == value:
			return
		pinned = value
		_update_visibility()

## The one door every tween comes through; a test sets `clock.manual` and steps.
var clock := TweenClock.new()

var _node: SkillNode = null
var _hovered: bool = false
var _flashing: bool = false
var _subs := SubBag.new()
var _bound: bool = false
var _bars: Array[Bar] = []
var _time: float = 0.0
var _fade_target: float = 0.0
var _fade_tween: Tween = null
var _flash_tween: Tween = null


func _ready() -> void:
	set_process(false)
	# In the editor the bars only preview their knobs ([method _preview]); the
	# live wiring is game-only.
	if not Engine.is_editor_hint():
		modulate.a = 0.0
		_wire()


func _wire() -> void:
	_node = owner as SkillNode
	if _node == null:
		return
	_node.hover_changed.connect(_on_hover_changed)
	_listen_settled()


func _enter_tree() -> void:
	if not Engine.is_editor_hint() and is_node_ready():
		_listen_settled()


## The spread cue's one listener on the CURRENT live world (re-checked on every
## ready/enter, since tests reset the live world): a static dispatcher, so a
## world turn costs O(changed), never a scan of every node's bars.
static func _listen_settled() -> void:
	var w := CombatWorld.live()
	var fn := Callable(TerrainBars, &"_on_terrain_settled")
	if not w.terrain_settled.is_connected(fn):
		w.terrain_settled.connect(fn)


static func _on_terrain_settled(changed: Array[NodeCombat]) -> void:
	for c in changed:
		var n := c.real() if c != null else null
		if n != null and is_instance_valid(n) and n.terrain_bars != null:
			n.terrain_bars.flash()


# ── Reads (static, pure over the node's accessors) ──────────────────────────

## One bar's blocks for [param count] stacks on a node of [param degree] with
## cap multiple [param k]: a block is `degree` stacks, so the frame is the cap
## and the first `t_per_degree` blocks are inert.
static func layout(count: int, degree: int, k: int, max_overflow: int) -> Layout:
	var l := Layout.new()
	if degree < 1 or k < 1:
		return l
	var per := TerrainRules.shared().t_per_degree
	var cap := Terrain.cap(degree, k)
	l.inert_blocks = per
	l.frame_blocks = k * per
	l.fill_blocks = float(clampi(count, 0, cap)) / degree
	if count > cap:
		@warning_ignore("integer_division")
		var over := (count - cap + degree - 1) / degree
		l.overflow_blocks = mini(over, maxi(max_overflow, 0))
	return l


## The temperature bar's element by the sign of t: Fire above 0, Ice below,
## null at 0.
static func temperature_element(t: int) -> Element:
	if t > 0:
		return TerrainSettle.element_on(Terrain.Axis.HEAT)
	if t < 0:
		return TerrainSettle.element_on(Terrain.Axis.COLD)
	return null


## The band [param band] displays as: itself, or the nearest band below it
## with an [Identity] (#1793 — Fire's and Lightning's overflow bands show as
## Burning and Shocked). Null when inert.
static func shown_band(element: Element, band: ElementBand) -> ElementBand:
	if element == null or band == null:
		return null
	var i := element.bands.find(band)
	while i >= 0:
		var b := element.bands[i]
		if b != null and b.identity != null:
			return b
		i -= 1
	return null


## THE name read (#1796): what [param element] is called on [param node] —
## `<name> <count>/<T>`. The name is the shown band's highest excess name the
## count passes ([member ElementBand.excess_names]: blaze, inferno), else the
## shown band's noun, else (inert) the terrain [StatusDef]'s name.
static func label_for(node: SkillNode, element: Element) -> String:
	var c := node.get_combat()
	var count := c.terrain_count(element)
	var t := c.terrain_threshold()
	var shown := shown_band(element, c.terrain_band(element))
	var name := ""
	if shown != null:
		name = excess_name(shown, count, t, c.terrain_cap())
		if name.is_empty():
			name = shown.identity.noun
	elif element.terrain != null:
		name = element.terrain.display_name
	elif element.identity != null:
		name = element.identity.noun
	return "%s %d/%d" % [name, count, t]


## [param band]'s excess name at [param count]: the entry with the highest
## threshold the count passes (`>` as [method Terrain.band_of]; the cap wins a
## tie with a multiple). Empty when none passes.
static func excess_name(band: ElementBand, count: int, t: int, cap: int) -> String:
	var best := ""
	var best_at := -1
	for key: int in band.excess_names:
		var at := cap if key == ElementBand.EXCESS_AT_CAP else key * t
		if count > at and (at > best_at or (at == best_at and key == ElementBand.EXCESS_AT_CAP)):
			best = band.excess_names[key]
			best_at = at
	return best


## The bars [param node] draws, temperature first: one per element with a
## nonzero count — so exactly one label per element.
static func bars_for(node: SkillNode, max_overflow: int) -> Array[Bar]:
	var out: Array[Bar] = []
	if node == null:
		return out
	var c := node.get_combat()
	var t := c.terrain_threshold()
	if t <= 0:
		return out
	var degree := node.get_graph_degree(node.get_graph())
	@warning_ignore("integer_division")
	var k := c.terrain_cap() / t
	for e: Element in [temperature_element(c.terrain_t()), TerrainSettle.element_on(Terrain.Axis.CHARGE)]:
		if e == null or c.terrain_count(e) <= 0:
			continue
		var b := Bar.new()
		b.element = e
		b.count = c.terrain_count(e)
		b.degree = degree
		b.color = e.identity.tint if e.identity != null else Color.WHITE
		var shown := shown_band(e, c.terrain_band(e))
		var id := shown.identity if shown != null else e.identity
		b.label_color = id.tint if id != null else b.color
		b.icon = id.icon if id != null else null
		b.label = label_for(node, e)
		b.layout = layout(b.count, degree, k, max_overflow)
		out.append(b)
	return out


# ── Show gate ───────────────────────────────────────────────────────────────

## Pinned, hovered or mid spread cue.
func is_shown() -> bool:
	return pinned or _hovered or _flashing


## The spread cue: fade in, hold [member flash_hold_s], fade out. A hovered or
## pinned node is already shown and does not flash.
func flash() -> void:
	if _node == null or _hovered or pinned:
		return
	_flashing = true
	_update_visibility()
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = clock.tween(self)
	_flash_tween.tween_interval(_FADE_IN_S + flash_hold_s)
	_flash_tween.tween_callback(_end_flash)


func _end_flash() -> void:
	_flashing = false
	_update_visibility()


func _on_hover_changed(hovered: bool) -> void:
	_hovered = hovered
	_update_visibility()


## The single gate: on screen and subscribed, or neither.
func _update_visibility() -> void:
	if _node == null:
		return
	if is_shown():
		if not _bound:
			_bound = true
			_subs.now(_node.terrain_changed, _refresh)
		_fade_to(1.0)
	else:
		_fade_to(0.0)
		if _bound:
			_bound = false
			_subs.clear()
		set_process(false)


func _fade_to(alpha: float) -> void:
	if is_equal_approx(_fade_target, alpha):
		return
	_fade_target = alpha
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = clock.tween(self)
	_fade_tween.tween_property(self, "modulate:a", alpha, _FADE_IN_S if alpha > 0.0 else _FADE_OUT_S)


## Re-read the bars and repaint; the flicker runs only while a tail is up.
func _refresh() -> void:
	if not is_node_ready() or Engine.is_editor_hint():
		queue_redraw()
		return
	_bars = bars_for(_node, max_overflow_blocks) if _node != null else []
	var tail := false
	for b in _bars:
		tail = tail or b.layout.overflow_blocks > 0
	set_process(_bound and tail)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


# ── Drawing ─────────────────────────────────────────────────────────────────

func _draw() -> void:
	var bars := _bars
	if Engine.is_editor_hint():
		bars = _preview()
	var font := ThemeDB.fallback_font
	var row := bar_height + gap * 2.0 + label_size
	for i in bars.size():
		_draw_bar(bars[i], south_offset + i * row, font)


func _draw_bar(bar: Bar, y: float, font: Font) -> void:
	var l := bar.layout
	var step := block_size + gap
	var x0 := -(l.frame_blocks * step - gap) * 0.5
	var charge := Terrain.axis_of(bar.element) == Terrain.Axis.CHARGE
	for i in l.frame_blocks:
		var r := Rect2(x0 + i * step, y, block_size, bar_height)
		var inert := i < l.inert_blocks
		draw_rect(r, _EMPTY_INERT if inert else _EMPTY_PRIMED)
		var f := clampf(l.fill_blocks - i, 0.0, 1.0)
		if f > 0.0:
			var fill := bar.color.darkened(0.35) if inert else bar.color
			draw_rect(Rect2(r.position, Vector2(block_size * f, bar_height)), fill)
		draw_rect(r, _FRAME, false, 1.0)
	if charge and bar.degree > 0:
		# One blip per stack inside the frame: Charge is counted, not just filled.
		var blip := block_size / bar.degree
		for s in mini(bar.count, l.frame_blocks * bar.degree):
			@warning_ignore("integer_division")
			var at := Vector2(x0 + (s / bar.degree) * step + (s % bar.degree + 0.5) * blip, y + bar_height * 0.5)
			draw_circle(at, maxf(blip * 0.25, 0.6), Color(1, 1, 1, 0.9))
	for j in l.overflow_blocks:
		var fade := 1.0 - float(j + 1) / (l.overflow_blocks + 1)
		var flicker := 0.6 + 0.4 * pingpong(2.0 * _time / maxf(flicker_period, 0.01) + j * 0.55, 1.0)
		var r := Rect2(x0 + (l.frame_blocks + j) * step, y, block_size, bar_height)
		draw_rect(r, Color(bar.color, fade * flicker))
	var ly := y + bar_height + gap + label_size
	var lx := x0
	if bar.icon != null:
		draw_texture_rect(bar.icon, Rect2(lx, ly - label_size, label_size, label_size), false)
		lx += label_size + gap
	draw_string(font, Vector2(lx, ly), bar.label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, bar.label_color)


## Editor feedback for the knobs: a sample bar, only in this scene's own editor tab.
func _preview() -> Array[Bar]:
	var out: Array[Bar] = []
	if not is_inside_tree() or get_tree().edited_scene_root != self:
		return out
	var b := Bar.new()
	b.degree = 1
	b.count = 9
	b.color = Color(0.9, 0.3, 0.2)
	b.label_color = b.color
	b.label = "Heat 9/2"
	b.layout = layout(b.count, 1, 3, max_overflow_blocks)
	out.append(b)
	return out
