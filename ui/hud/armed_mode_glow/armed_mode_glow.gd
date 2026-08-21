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

@onready var _rect: ColorRect = %GlowRect

var _input_ctl: PlayerInputController


func _ready() -> void:
	layer = LAYER
	_rect.color = Color.TRANSPARENT
	_rect.visible = false


## Injected by [HudRoot.compose]. Connects to the one signal and immediately
## reads the current value, so arming that happened before compose still shows.
func bind(input_ctl: PlayerInputController) -> void:
	_input_ctl = input_ctl
	if _input_ctl == null:
		return
	_input_ctl.armed_tint_changed.connect(_on_armed_tint_changed)
	_on_armed_tint_changed(_input_ctl.get_armed_tint())


func _on_armed_tint_changed(tint: Color) -> void:
	# Alpha is the armed/unarmed switch, not a dimmer — per `Emissive`'s house
	# rule the shader's spatial mask does the fading and the colour value does
	# the brightness, so a fully-opaque HDR colour is exactly what we want here.
	_rect.color = tint
	_rect.visible = tint.a > 0.0
