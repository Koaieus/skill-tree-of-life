class_name ArmedModeGlow
extends CanvasLayer

## Viewport-wide inward border glow while an attack mode is armed (#412).
##
## The ambient "you are currently armed with X" signal: without it the only
## feedback is the AttackModeBar button's selected state, which is easy to miss
## mid-click, so players click a node expecting a plain allocate and land in
## Ranged or Magic targeting instead.
##
## **A pure consumer.** It asks [PlayerInputController] for one resolved colour
## and paints it. It deliberately does NOT subscribe to the five per-mode arm
## signals and re-derive which one wins — that ordering is the `_armed_modes`
## pop stack's to own, and a second copy of it here would rot the moment a
## sixth [ArmedMode] is added.
##
## Sits at [constant LAYER] — above the world, below the HUD (**owner call
## 2026-08-21**: the glow frames the play area and the tray / left column /
## minimap draw on top of it, unobstructed). Both that and the HUD's own layer
## stay under `default_game_env.tres`'s `background_canvas_max_layer = 100`, so
## the glow still reaches the bloom pass.

## Draw order. Must be > 0 (the root viewport's default canvas, where the graph
## lives) so the glow is not hidden behind the world, and < the HUD CanvasLayer's
## own layer in `scenes/game_root.tscn` so HUD panels stay on top.
const LAYER: int = 1

## How far above the bloom threshold the glow burns, in STOPS (+1 stop = x2
## linear). This is the brightness dial — `band_px` / `falloff` on the shader
## control the glow's *shape*, this controls its *energy*.
##
## The named tiers from [Emissive] are the landmarks on this slider:
## `INERT 0.0` · `LABEL 0.5` · `VALUE 1.0` · `ALERT 2.0` · `PEAK 3.0`.
## `docs/domain/hdr-color.md` asks that shipped values LAND on a tier rather
## than between two — the slider is here so you can find out *which* tier, not
## so the answer can be 1.35 forever. Note anything at or below `INERT` cannot
## bloom at all; it just tints.
##
## Applied with [method Emissive.tint_peak], not [method Emissive.tint]: over a
## large additive area `tint`'s luminance normalisation drags the off-hue
## channels to ~1.0 and the glow goes white. See `hdr-color.md`.
@export_range(0.0, 3.0, 0.05) var glow_stops: float = Emissive.VALUE:
	set(value):
		glow_stops = value
		_repaint()

@onready var _rect: ColorRect = %GlowRect

var _input_ctl: PlayerInputController

## Last colour received from the input controller, at its authored `StatDef`
## value — UNLIFTED. Kept so a `glow_stops` change can re-lift without waiting
## for the next arm.
var _base_tint: Color = Color.TRANSPARENT


func _ready() -> void:
	layer = LAYER
	_repaint()


## Injected by [HudRoot.compose]. Connects to the one signal and immediately
## reads the current value, so arming that happened before compose still shows.
func bind(input_ctl: PlayerInputController) -> void:
	_input_ctl = input_ctl
	if _input_ctl == null:
		return
	_input_ctl.armed_tint_changed.connect(_on_armed_tint_changed)
	_on_armed_tint_changed(_input_ctl.get_armed_tint())


func _on_armed_tint_changed(tint: Color) -> void:
	_base_tint = tint
	_repaint()


## Lift the stored identity colour to [member glow_stops] and hand it to the
## rect. Alpha stays the armed/unarmed switch, never a dimmer — per `Emissive`'s
## house rule the shader's spatial mask does the fading and the colour value
## does the brightness, so what reaches the rect is fully opaque or invisible.
func _repaint() -> void:
	if _rect == null:
		return  # a `glow_stops` write before _ready(); _ready repaints.
	var lit := Color.TRANSPARENT
	if _base_tint.a > 0.0:
		lit = Emissive.tint_peak(_base_tint, glow_stops)
	_rect.color = lit
	_rect.visible = lit.a > 0.0
