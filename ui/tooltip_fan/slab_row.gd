@tool
class_name SlabRow
extends Control

## One line of text rendered as its own mini slab — a single Label on a
## [SlabPanel] background tinted by whatever colour the caller hands it (#343
## visual spec: dark fill, bright tint border reading as glowing, text in the
## same tint mixable toward pure white — the PoE prefix/suffix-row reading
## surface).
##
## [b]This is the generic half of [ModSlabRow][/b], extracted in #588 so the
## frontmatter's hover tooltip can be a stack of these without dragging the
## stat system in behind it. Everything here is content-agnostic: give it a
## string and a [Color]. [ModSlabRow] is an INHERITED SCENE of
## `slab_row.tscn` that adds exactly one thing — resolving those two from a
## [StatModifier].
##
## The row sizes to its label (#343 part 1): [method _get_minimum_size] is the
## label's height plus the scene's vertical insets.
##
## [b]The label does NOT autowrap[/b], and that is deliberate (#588). A
## single-line row's minimum height is known without reference to any width, so
## there is no width→height→width path at all — the strongest form of the
## "no cycle exists" property this extraction was done to get. A stack of these
## widens to its longest row instead of wrapping within a fixed one. Inherited
## behaviour, not a change: [ModSlabRow] never autowrapped either (the wording
## this doc replaced claimed it did, and was wrong on both).
##
## Reveal is driven externally via [method set_progress] against the shared
## fixed-clock / progress(0..1) contract (see fan_panel.gd / docs/domain/
## tooltip-fan.md) — this row owns no Tween, matching the other #293 rows
## (PanelHeader, StatValueRow, AddonItem). It must render correctly the moment
## [method bind_text] is called, with no assumption about whether/when
## [method set_progress] is ever invoked.

## Scale the row starts at when [method set_progress]'s `t` is 0.
@export_range(0.5, 1.0, 0.01) var start_scale: float = 0.92

## Text colour mixes slab-tint → pure white: 0 = raw tint, 1 = full white.
## Full white is for the highest-emphasis rows; tint-leaning is the default.
@export_range(0.0, 1.0, 0.01) var text_tint_mix: float = 0.35:
	set(v):
		text_tint_mix = v
		_refresh_label_color()

## EV stops (see [Emissive]) the text is lifted by after the tint/white mix.
## Defaults to [constant Emissive.VALUE] — text was previously authored
## purely SDR (mix toward white, never past 1.0) and never cleared bloom
## threshold regardless of [member text_tint_mix].
@export_range(0.0, 3.0, 0.05) var text_glow_stops: float = Emissive.VALUE:
	set(v):
		text_glow_stops = v
		_refresh_label_color()

## Vertical label inset in pixels — must match the Label node's authored
## top/bottom offsets so [method _get_minimum_size] reports the true height.
const _V_INSET := 4.0

@onready var _slab: SlabPanel = %Slab
## Test-compat alias onto the same node: `test_mod_slab_row.gd` reads
## `_background.color` for the raw-tint contract, so the base [ColorRect]
## property is kept in sync with the shader's `tint_color` (it is inert under
## a ShaderMaterial — the shader is what renders).
@onready var _background: ColorRect = %Slab
@onready var _label: Label = %Label


func _ready() -> void:
	if _slab:
		_refresh_label_color()
		# Not about wrapping (this label never wraps — see the class doc):
		# a font or theme change alters the label's measured height, and
		# this row's minimum has to follow it.
		_label.resized.connect(update_minimum_size)
	if Engine.is_editor_hint():
		# Author-time: show the row fully revealed so its content is
		# witnessable while editing. Pure visual setup, safe under @tool
		# (mirrors FanPanel's / FanTrace's own editor-hint branch).
		set_progress(1.0)
		return
	# Rest state is t = 0 (#221 §4) — the caller drives the reveal, and it is
	# NOT a side effect of an entry call. Without this a freshly instantiated
	# row sits at full scale/alpha until something ticks it, so a consumer
	# animating 0 → 1 pops to full for a frame first. That is the exact bug
	# #293 closed for AddonItem; the row must not reintroduce it for bare
	# consumers like #306's toast.
	set_progress(0.0)


## Renders [param text] on a slab tinted [param tint], with the label colour
## derived from that tint via [member text_tint_mix] / [member text_glow_stops].
## The whole of what this row does — subclasses resolve the two arguments.
func bind_text(text: String, tint: Color) -> void:
	_label.text = text
	_slab.tint_color = tint
	_background.color = tint
	_refresh_label_color()
	# New text is a different WIDTH (never a different number of lines — this
	# label does not wrap), so this row's minimum changes; recompute it now
	# and the parent container re-sorts on the next layout pass.
	update_minimum_size()


## Text colour = tint mixed [member text_tint_mix] toward pure white.
func _refresh_label_color() -> void:
	if _label == null or _slab == null:
		return
	var mixed := _slab.tint_color.lerp(Color.WHITE, text_tint_mix)
	_label.add_theme_color_override("font_color", Emissive.at(mixed, text_glow_stops))


## The row is exactly its label plus the scene's vertical insets — height is
## content-driven (#343). The label is single-line, so this is one line's
## height plus insets and nothing here depends on the row's own width, which
## is what keeps the stack cycle-free (#588). Width is left to the container.
func _get_minimum_size() -> Vector2:
	if _label == null:
		return Vector2.ZERO
	return Vector2(0.0, _label.get_minimum_size().y + _V_INSET * 2.0)


## Applies the fan reveal at clock position `t` (0..1): cubic ease-out driving
## scale (start_scale → 1.0) and fade (0 → 1). Matches [method FanPanel.set_progress].
func set_progress(t: float) -> void:
	var eased := _ease_out(clampf(t, 0.0, 1.0))
	scale = Vector2.ONE * lerpf(start_scale, 1.0, eased)
	var m := modulate
	m.a = eased
	modulate = m


static func _ease_out(t: float) -> float:
	var inv := 1.0 - t
	return 1.0 - inv * inv * inv
