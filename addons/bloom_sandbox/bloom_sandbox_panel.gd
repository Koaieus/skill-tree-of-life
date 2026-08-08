@tool
extends PanelContainer
## Bloom sandbox — the reference chart for #371's glow pass, and the live dial
## for tuning it.
##
## Two jobs:
##
## 1. **Reference.** Squares and text at I = −1 / 0 / +1 / +2 / +3, drawn over
##    both a dark fill and a bright one — because the bloom threshold applies to
##    the *composited pixel*, not to the element. The same tier over a bright
##    world pixel blooms differently, and that is the single most confusing thing
##    about authoring emissive content.
##
## 2. **The dial.** The sliders edit `default_game_env.tres` **in place** — the
##    very resource the game and every other sandbox panel share — so what you
##    see here is what ships. Nothing is written to disk until you press Save.
##
## Diagnostic worth knowing: if the +1 / +2 / +3 rows ever read as one identical
## clipped white, the tonemapper is compressing them, and no amount of threshold
## fiddling will separate them.
##
## See `docs/domain/hdr-color.md` for the stop → encoded-`Color` derivation.

const _ENV_PATH := "res://ui/theme/default_game_env.tres"

## The chart's rows. Note −1 is included deliberately: it is the only way to see
## what "below the floor" looks like next to the tiers that clear it.
const _STOPS: Array[float] = [-1.0, 0.0, 1.0, 2.0, 3.0]

## Bases the chart is drawn in. Neutral first (the untinted default), then a few
## identity hues, so you can see that a saturated base clears the threshold in
## some channels before others.
const _BASES: Array[Dictionary] = [
	{"name": "neutral", "color": Color(0.8586, 0.9018, 0.9482)},
	{"name": "cyan", "color": Color(0.0, 0.72, 0.881)},
	{"name": "crimson", "color": Color(0.8878, 0.203, 0.2233)},
	{"name": "gold", "color": Color(0.8909, 0.7204, 0.2596)},
]

## Slider specs: property, label, min, max, step. `glow_levels/N` are here
## because level weights — not intensity — are what decide whether glow reads as
## a tight core (levels 1–2) or a wide neon rim (levels 4–7).
const _SLIDERS: Array[Array] = [
	["glow_intensity", "Intensity", 0.0, 8.0, 0.05],
	["glow_strength", "Strength", 0.0, 2.0, 0.01],
	["glow_hdr_threshold", "HDR threshold", 0.0, 4.0, 0.01],
	["glow_hdr_scale", "HDR scale", 0.0, 4.0, 0.01],
	["glow_bloom", "Bloom (lifts ALL pixels)", 0.0, 1.0, 0.01],
	["glow_levels/1", "Level 1 (tightest)", 0.0, 2.0, 0.05],
	["glow_levels/2", "Level 2", 0.0, 2.0, 0.05],
	["glow_levels/3", "Level 3", 0.0, 2.0, 0.05],
	["glow_levels/4", "Level 4", 0.0, 2.0, 0.05],
	["glow_levels/5", "Level 5", 0.0, 2.0, 0.05],
	["glow_levels/6", "Level 6", 0.0, 2.0, 0.05],
	["glow_levels/7", "Level 7 (widest)", 0.0, 2.0, 0.05],
]

const _BLEND_MODES: Array[String] = ["Additive", "Screen", "Softlight", "Replace", "Mix"]

## Shapes, in ascending lit-pixel density. This axis matters as much as the stop
## axis: bloom accumulates from *neighbouring* lit pixels, so a hairline and a
## filled rect at the identical colour glow completely differently. Tune against
## the row that matches the thing you are actually lighting — the rim arcs and
## edges this project mostly wants to light are strokes, not fills.
const _SHAPES: Array[Dictionary] = [
	{"name": "hairline", "kind": ShapeCell.HAIRLINE},
	{"name": "stroke", "kind": ShapeCell.STROKE},
	{"name": "ring", "kind": ShapeCell.RING},
	{"name": "arc", "kind": ShapeCell.ARC},
	{"name": "disc", "kind": ShapeCell.DISC},
	{"name": "outline", "kind": ShapeCell.OUTLINE},
	{"name": "fill", "kind": ShapeCell.FILL},
]

const CHART_ROW_SEPARATION := 32  # value in pixels

## The six real attribute `StatDef`s, read live off `StatRegistry` rather than
## re-declaring their colours here — the "archetypes" band exists specifically
## to catch a StatDef.tint_color edit going stale, which a hardcoded copy
## could never do.
const _ARCHETYPE_STATS: Array[StringName] = [
	&"strength", &"dexterity", &"intelligence", &"wisdom", &"perception", &"constitution",
]


## A single primitive drawn at one emissive value. Exists because bloom reads
## *coverage*, and a chart made only of filled rects teaches the wrong lesson.
class ShapeCell:
	extends Control

	enum { HAIRLINE, STROKE, RING, ARC, DISC, OUTLINE, FILL }

	var kind: int = FILL
	var tint: Color = Color.WHITE

	func _init(p_kind: int, p_tint: Color) -> void:
		kind = p_kind
		tint = p_tint
		custom_minimum_size = Vector2(96.0, 46.0)

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var mid := size * 0.5
		var radius: float = minf(size.x, size.y) * 0.36
		match kind:
			HAIRLINE:
				draw_line(Vector2(6.0, mid.y), Vector2(size.x - 6.0, mid.y), tint, 1.0, true)
			STROKE:
				draw_line(Vector2(6.0, mid.y), Vector2(size.x - 6.0, mid.y), tint, 5.0, true)
			RING:
				draw_arc(mid, radius, 0.0, TAU, 48, tint, 2.0, true)
			ARC:
				# The rim-arc case specifically: a thick partial ring, which is what
				# `rim_ring.gdshader` paints for a lit slot.
				draw_arc(mid, radius, -0.9, 1.5, 32, tint, 6.0, true)
			DISC:
				draw_circle(mid, radius, tint)
			OUTLINE:
				draw_rect(rect.grow(-8.0), tint, false, 2.0)
			FILL:
				draw_rect(rect.grow(-8.0), tint)

@onready var _rows: HBoxContainer = %Rows
@onready var _knobs: VBoxContainer = %Knobs
@onready var _picker: ColorPicker = %Picker
## The live sample lives INSIDE the bloom viewport — a swatch in the sidebar
## would render in the editor's own viewport and could never glow.
@onready var _picker_swatch: ColorRect = %PickerSwatch
@onready var _picker_text: Label = %PickerText
## The numeric readout, in the sidebar, where it must stay inert to be legible.
@onready var _picker_label: Label = %PickerLabel
@onready var _world: SubViewport = %World
@onready var _save_button: Button = %SaveButton
@onready var _reset_button: Button = %ResetButton
@onready var _diagnostics: Label = %Diagnostics
@onready var _status: Label = %Status
@onready var left: VBoxContainer = %VBoxContainer
@onready var right: VBoxContainer = %VBoxContainer2
@onready var archetypes: VBoxContainer = %VBoxContainer3
@onready var _strategy_picker: OptionButton = %StrategyPicker

var _env: Environment
## Filled in by `_probe_render_target()` one frame after the first draw.
var _render_target_note := "probing…"

## Candidate `Emissive` equalization strategies, compared live in the
## "archetypes" band — see `ui/theme/emissive.gd`'s `tint_peak`/`tint_damped`
## doc comments for what each is trying to fix and why it's a candidate, not
## an adopted default. Built in `_ready()`, not `const`, because a `Callable`
## to a static method isn't a const-foldable literal.
var _strategies: Array[Dictionary] = []
## Index into `_strategies`. Defaults to `tint()` — the one actually in use
## everywhere else (Edge, SlabPanel) today.
var _strategy_index: int = 1


## No-op: the bloom chart is self-contained and routes no inspected resource.
func load_object(_obj: Object) -> void:
	pass


func _ready() -> void:
	# Ask the viewport for the Environment its glow pass is actually running,
	# rather than `load()`ing the path and trusting the resource cache to have
	# handed both of us the same object. That assumption held in a game run and
	# silently did not in the editor, which is what made every slider here inert.
	# `%WorldEnvironment` can't cross the instance boundary, so `bloom_viewport.gd`
	# exposes it — see `docs/domain/hdr-color.md`.
	_env = _world.get_environment_resource()

	_strategies = [
		{"name": "at() — no correction", "fn": Callable(Emissive, "at")},
		{"name": "tint() — luminance-normalized (current)", "fn": Callable(Emissive, "tint")},
		{"name": "tint_peak() — max-channel normalized", "fn": Callable(Emissive, "tint_peak")},
		{"name": "tint_damped() — half-luminance-normalized", "fn": Callable(Emissive, "tint_damped")},
	]

	_build_chart()
	_build_knobs()
	_build_strategy_picker()
	_build_diagnostics()
	_probe_render_target()

	# `edit_intensity` is the `I` slider — the ergonomic way to author an HDR
	# colour. It is the same conversion `Emissive.at()` does in code, so a colour
	# dialled here can be transcribed verbatim into a tier constant.
	_picker.edit_intensity = true
	_picker.color = Emissive.neutral(Emissive.VALUE)
	_picker.color_changed.connect(_on_picked)
	_on_picked(_picker.color)

	_save_button.pressed.connect(_save_env)
	_reset_button.pressed.connect(_reset_env)


# --- the chart -------------------------------------------------------------

## Two columns: colour on the left, coverage on the right. `%Rows` is an HBox and
## the render target is fixed-size, so the chart never reflows and never clips —
## the surrounding ScrollContainer handles a small panel.
func _build_chart() -> void:
	for child in left.get_children():
		child.queue_free()

	# The same tier composites differently against a dark fill and a lit one, and
	# the threshold sees the composite — hence two backdrops. The bright band is
	# neutral-only: one row makes the point, four would just cost height.
	_add_band(left, "bases  ·  over dark fill", Color(0.04, 0.05, 0.07), _base_rows)
	_add_band(left, "neutral  ·  over bright fill", Color(0.55, 0.58, 0.62), _neutral_row)

	for child in right.get_children():
		child.queue_free()
		
	# Coverage over dark only — doubling this axis across backdrops teaches
	# nothing the left column hasn't already shown.
	_add_band(right, "shapes  ·  neutral base, over dark fill", Color(0.04, 0.05, 0.07), _shape_rows)

	_build_archetype_band()


func _add_band(host: Control, title: String, backdrop: Color, rows: Callable) -> void:
	var band := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = backdrop
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	band.add_theme_stylebox_override("panel", style)
	host.add_child(band)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", CHART_ROW_SEPARATION)
	band.add_child(col)

	var heading := Label.new()
	heading.text = title
	# Deliberately inert: the chrome must never compete with the samples.
	heading.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))
	col.add_child(heading)

	col.add_child(_stop_header())
	for row in rows.call():
		col.add_child(row)


## Rows of the colour-family chart: one base per row, one tier per column.
func _base_rows() -> Array[HBoxContainer]:
	var out: Array[HBoxContainer] = []
	for base_spec in _BASES:
		out.append(_sample_row(base_spec["name"], base_spec["color"]))
	return out


## The bright-backdrop band: neutral only. One row carries the whole lesson —
## that the composite, not the element, is what crosses the threshold.
func _neutral_row() -> Array[HBoxContainer]:
	var out: Array[HBoxContainer] = []
	out.append(_sample_row("neutral", Emissive.NEUTRAL))
	return out


## Rows of the coverage chart: one primitive per row, one tier per column.
func _shape_rows() -> Array[HBoxContainer]:
	var out: Array[HBoxContainer] = []
	for shape in _SHAPES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_gutter(shape["name"], Color(0.55, 0.6, 0.65)))
		for stops in _STOPS:
			row.add_child(ShapeCell.new(shape["kind"], Emissive.neutral(stops)))
		out.append(row)
	return out


## The live A/B surface for "does this equalization strategy actually read as
## equally hot across hues" — the six real `StatDef.tint_color`s, run through
## whichever `_strategies[_strategy_index]` is selected. Its own band (not
## folded into `left`/`right`) so switching strategy only rebuilds this,
## not the whole chart.
func _build_archetype_band() -> void:
	for child in archetypes.get_children():
		child.queue_free()

	var strategy: Callable = _strategies[_strategy_index]["fn"]
	var band := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.07)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	band.add_theme_stylebox_override("panel", style)
	archetypes.add_child(band)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", CHART_ROW_SEPARATION)
	band.add_child(col)

	var heading := Label.new()
	heading.text = "archetypes  ·  equalization strategy"
	heading.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))
	col.add_child(heading)

	col.add_child(_stop_header())
	for stat_id in _ARCHETYPE_STATS:
		var def := StatRegistry.get_def(stat_id)
		var base := def.tint_color if def != null else Color.DIM_GRAY
		var label := def.abbrev if def != null and not def.abbrev.is_empty() else String(stat_id)
		col.add_child(_sample_row(label, base, strategy))


## The archetype band's strategy dropdown (`%StrategyPicker`, scene-authored
## in the SIDEBAR, not built here) drives the chart via this wiring only.
## It lives in the sidebar, not inside the chart it controls, because
## `OptionButton`'s popup is a real `Window` and can't position itself
## against content rendered inside a `SubViewport` — the symptom is a
## dropdown that silently never opens. Every other interactive control in
## this panel (blend mode, sliders, Save/Reset) is in the sidebar for the
## same reason.
func _build_strategy_picker() -> void:
	for i in _strategies.size():
		_strategy_picker.add_item(_strategies[i]["name"], i)
	_strategy_picker.selected = _strategy_index
	_strategy_picker.item_selected.connect(func(i: int) -> void:
		_strategy_index = i
		_build_archetype_band())


func _stop_header() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_gutter("", Color(0.5, 0.55, 0.6)))
	for stops in _STOPS:
		var cell := Label.new()
		cell.custom_minimum_size = Vector2(96.0, 0.0)
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.text = "I = %+.0f" % stops
		cell.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))
		row.add_child(cell)
	return row


## `strategy` defaults to `Emissive.at` (the chart's baseline everywhere else);
## the archetype-equalization band is the one caller that swaps it out.
func _sample_row(base_name: String, base: Color, strategy: Callable = Callable(Emissive, "at")) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_gutter(base_name, Color(0.55, 0.6, 0.65)))
	for stops in _STOPS:
		row.add_child(_sample(base, stops, strategy))
	return row


func _gutter(text: String, tint: Color) -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(70.0, 0.0)
	label.text = text
	label.add_theme_color_override("font_color", tint)
	return label


## A square and a glyph at the same value — because coverage is half the effect.
## The square emits over its whole area; the glyph only along its strokes, which
## is why a small label blooms far less than a swatch of the identical colour.
func _sample(base: Color, stops: float, strategy: Callable = Callable(Emissive, "at")) -> VBoxContainer:
	var value: Color = strategy.call(base, stops)

	var cell := VBoxContainer.new()
	cell.custom_minimum_size = Vector2(96.0, 0.0)
	cell.add_theme_constant_override("separation", CHART_ROW_SEPARATION)

	var square := ColorRect.new()
	square.custom_minimum_size = Vector2(96.0, 36.0)
	square.color = value
	cell.add_child(square)

	var glyph := Label.new()
	glyph.text = "Wg 128"
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.add_theme_color_override("font_color", value)
	glyph.add_theme_font_size_override("font_size", 22)
	cell.add_child(glyph)

	return cell


# --- the knobs -------------------------------------------------------------

func _build_knobs() -> void:
	# `remove_child` before `queue_free`: Reset rebuilds these in the same frame,
	# and a queue_free'd node is still a child until the frame ends — leaving two
	# sets of sliders stacked, the second of which is the live one.
	for child in _knobs.get_children():
		_knobs.remove_child(child)
		child.queue_free()
	# A null env means the viewport handed back nothing; `_build_diagnostics` says
	# so on screen. Bail rather than throwing a wall of errors over the message.
	if _env == null:
		return

	var enabled := CheckBox.new()
	enabled.text = "Glow enabled"
	enabled.button_pressed = _env.glow_enabled
	enabled.toggled.connect(func(on: bool) -> void:
		_env.glow_enabled = on
		_build_diagnostics())
	_knobs.add_child(enabled)

	var blend := OptionButton.new()
	for i in _BLEND_MODES.size():
		blend.add_item(_BLEND_MODES[i], i)
	blend.selected = _env.glow_blend_mode
	blend.item_selected.connect(func(i: int) -> void:
		_env.glow_blend_mode = i
		_build_diagnostics())
	_knobs.add_child(_labelled("Blend mode", blend))

	for spec in _SLIDERS:
		_knobs.add_child(_slider(spec[0], spec[1], spec[2], spec[3], spec[4]))


func _slider(property: String, text: String, low: float, high: float, step: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var label := Label.new()
	var readout := func(v: float) -> void: label.text = "%s  %.2f" % [text, v]
	box.add_child(label)

	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = _env.get(property)
	slider.value_changed.connect(func(v: float) -> void:
		_env.set(property, v)
		readout.call(v)
		# Keep the threshold/intensity lines honest while you drag — a stale
		# readout next to a live chart is worse than none.
		_build_diagnostics())
	box.add_child(slider)

	readout.call(slider.value)
	return box


func _labelled(text: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var label := Label.new()
	label.text = text
	box.add_child(label)
	box.add_child(control)
	return box


# --- the picker ------------------------------------------------------------

func _on_picked(color: Color) -> void:
	_picker_swatch.color = color
	_picker_text.add_theme_color_override("font_color", color)
	# Linear luminance is what the threshold actually compares against, so print
	# it next to the encoded channels — the encoded number alone tells you very
	# little about whether a colour will bloom.
	var lin := color.srgb_to_linear()
	var luminance := 0.2126 * lin.r + 0.7152 * lin.g + 0.0722 * lin.b
	var threshold: float = _env.glow_hdr_threshold if _env != null else 1.0
	_picker_label.text = "Color(%.4f, %.4f, %.4f)\nlinear luminance %.3f  (threshold %.2f)\n%s" % [
		color.r, color.g, color.b, luminance, threshold,
		"BLOOMS" if luminance > threshold else "inert",
	]


# --- diagnostics -----------------------------------------------------------

## Every silent failure mode of the glow pass, printed on open.
##
## This exists because the tab shipped broken and *looked* fine: the chart drew,
## so the viewport was clearly rendering, and there was nothing on screen to say
## which of the four ways glow does nothing was in play. All of it is cheap to
## read and none of it is inferable by looking. The instance-id line is the one
## that matters most — a mismatch means the sliders are driving an orphan copy.
func _build_diagnostics() -> void:
	if _env == null:
		_diagnostics.text = "NO ENVIRONMENT — %World handed back null. The packaged\nWorldEnvironment is missing or has no environment set."
		return
	var cached := load(_ENV_PATH) as Environment
	# The one that discriminates "the pass isn't running" from "the Environment
	# never reached the renderer": `WorldEnvironment` registers by writing the
	# resource onto its viewport's World3D. If this reads null, no amount of
	# correct Environment tuning can matter — nothing is holding it.
	var world := _world.find_world_3d()
	var registered: Environment = world.environment if world != null else null
	_diagnostics.text = "\n".join([
		# Compatibility always renders 2D in low dynamic range, so `use_hdr_2d` is
		# ignored there and no amount of Environment tuning can produce a glow.
		"renderer          %s / %s" % [
			RenderingServer.get_current_rendering_method(),
			RenderingServer.get_current_rendering_driver_name(),
		],
		"use_hdr_2d        %s" % _world.use_hdr_2d,
		"own_world_3d      %s" % _world.own_world_3d,
		"update_mode       %s" % _world.render_target_update_mode,
		"glow_enabled      %s" % _env.glow_enabled,
		"blend_mode        %s" % _BLEND_MODES[_env.glow_blend_mode],
		"threshold         %.2f" % _env.glow_hdr_threshold,
		"intensity         %.2f" % _env.glow_intensity,
		"env id (rendered) %s" % _env.get_instance_id(),
		"env id (cached)   %s  %s" % [
			cached.get_instance_id() if cached != null else "null",
			"✓ same" if cached == _env else "✗ DIFFERENT — sliders drive an orphan",
		],
		"world3d env       %s" % (
			"✓ registered" if registered == _env
			else "✗ NOT REGISTERED — WorldEnvironment never took"
		),
		"render target     %s" % _render_target_note,
	])


## The render target's pixel format is the ground truth for `use_hdr_2d`: the flag
## can read `true` on the node while the target was allocated 8-bit anyway, and an
## 8-bit target clamps at 1.0, so nothing can ever exceed the threshold. Probed
## once, after a drawn frame — the texture does not exist before then.
func _probe_render_target() -> void:
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var texture := _world.get_texture()
	var image := texture.get_image() if texture != null else null
	if image == null:
		_render_target_note = "unavailable"
		_build_diagnostics()
		return
	# Any float format clears the 1.0 ceiling. Forward+ reports RGBH here, not the
	# RGBAH you'd guess from "RGBA16F" — checking for one exact format reported a
	# correct HDR target as broken.
	var format := image.get_format()
	var hdr := format in [
		Image.FORMAT_RGBH, Image.FORMAT_RGBAH, Image.FORMAT_RGBF, Image.FORMAT_RGBAF,
	]
	_render_target_note = "format %d  %s" % [
		format, "✓ HDR" if hdr else "✗ not HDR — clamps at 1.0",
	]
	_build_diagnostics()


# --- persistence -----------------------------------------------------------

## The sliders mutate the shared resource in memory; this is what makes it
## permanent. Saving hits the file every other viewport reads, which is the
## whole point — one dial, not a per-surface copy.
func _save_env() -> void:
	if _env == null:
		return
	var err := ResourceSaver.save(_env, _ENV_PATH)
	if err == OK:
		_status.text = "Saved %s" % _ENV_PATH
	else:
		_status.text = "Save FAILED (%s)" % error_string(err)


## Discard unsaved slider drags — the way back once you've dialled somewhere bad.
##
## Two things this must not do. It must not keep a second hardcoded copy of the
## defaults (it would drift from the `.tres` the day anyone tunes). And it must
## not reach for a plain `load()`: that returns the **already-mutated cached
## instance**, so the reset would silently no-op. `CACHE_MODE_IGNORE` is what
## actually re-reads the file.
##
## The properties are copied *onto* the live object rather than `_env` being
## reassigned — the viewport's WorldEnvironment holds the original, and swapping
## our reference would just orphan us again.
func _reset_env() -> void:
	if _env == null:
		return
	var pristine := ResourceLoader.load(
		_ENV_PATH, "", ResourceLoader.CACHE_MODE_IGNORE
	) as Environment
	if pristine == null:
		_status.text = "Reset FAILED — could not re-read %s" % _ENV_PATH
		return
	for prop in pristine.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_STORAGE:
			_env.set(prop["name"], pristine.get(prop["name"]))
	_build_knobs()
	_build_diagnostics()
	_on_picked(_picker.color)
	_status.text = "Reset to the values on disk (nothing written)."
