class_name ArmedModeIcon
extends CanvasLayer

## Cursor-following badge showing what the next click will do while any armed
## mode is up (#664).
##
## The SECOND armed-mode channel, beside [ArmedModeGlow]'s viewport border. The
## glow is peripheral and says *what am I wielding*; this is foveal and says
## *what does my next click do*. They read opposite ends of the same pop stack
## on purpose — see [method PlayerInputController._armed_icon_level]. Nine armed
## states share three glow colours, so the glow alone cannot tell Clamp from
## Spike, or Deallocate from Stake from Extract; four of the nine have no glow
## at all and were previously unsignalled.
##
## The rule this creates, and which the player learns for free: **a badge means
## your click is modal. No badge means the plain default allocate.** That holds
## only because `ManageVerb.ALLOCATE` is deliberately not an [ArmedMode].
##
## **A pure consumer.** It takes one resolved (texture, colour) pair from
## [PlayerInputController] and draws it. It does NOT subscribe to the per-mode
## arm signals and re-derive which level wins — that ordering belongs to the
## `_armed_modes` stack, and a second copy here would rot the moment a tenth
## armed state lands.
##
## **Not [method Input.set_custom_mouse_cursor].** An OS cursor composites
## outside the viewport, so it could never use the [Emissive]/`Tier*` colour
## language (`.claude/rules/hdr-color.md`); it is also size-capped and cannot do
## per-frame state.
##
## Sits at [constant LAYER] — **above** the HUD, the inverse of
## [constant ArmedModeGlow.LAYER]. The glow frames the play area and the tray
## draws over it (owner call 2026-08-21); a cursor badge must never be occluded
## by anything.

## Draw order. Above the HUD's own CanvasLayer (2, `scenes/game_root.tscn`) so
## no panel can cover the badge, and below `default_game_env.tres`'s
## `background_canvas_max_layer = 100` so it still reaches the bloom pass at
## all. See `ui/z_layers.gd` for the full CanvasLayer stack.
const ZLayers = preload("res://ui/z_layers.gd")
const LAYER: int = ZLayers.ARMED_MODE_ICON

## Offset from the cursor hotspot to the badge's top-left, in pixels. Bottom-
## RIGHT of the hotspot, the OS drag-badge convention: the crosshair marks the
## exact hotspot, the badge trails south-east and so never covers the node
## being aimed at.
const OFFSET := Vector2(12, 12)

## How far above the bloom threshold the badge burns, in STOPS.
##
## Landed near-[constant Emissive.INERT] on purpose, and this is the one dial
## on this scene worth being careful with. Rendering in-viewport means the badge
## *can* bloom; that must not become *therefore it does*. A bloom halo on a 24px
## glyph is exactly what destroys small-glyph legibility — the in-viewport
## rendering is justified by needing the colour language, not by wanting glow.
##
## Tiers: `INERT 0.0` · `LABEL 0.5` · `VALUE 1.0` · `ALERT 2.0` · `PEAK 3.0`.
## `docs/domain/hdr-color.md` asks shipped values to LAND on a tier. Anything at
## or below `INERT` cannot bloom at all; it just tints.
@export_range(0.0, 3.0, 0.05) var glow_stops: float = Emissive.LABEL:
	set(value):
		glow_stops = value
		_repaint()

@onready var _badge: Control = %Badge
@onready var _texture_rect: TextureRect = %IconTexture

var _input_ctl: PlayerInputController

## Holds this bind's connections so a rebind drops them wholesale, rather than
## a per-site `is_connected` guard (`.claude/rules/ui-subscriptions.md`).
var _subs := BindScope.new()

## Last pair received, at its authored value — UNLIFTED, so a `glow_stops`
## change can re-lift without waiting for the next arm. Same split
## [ArmedModeGlow] uses.
var _icon: Texture2D = null
var _tint: Color = Color.TRANSPARENT


func _ready() -> void:
	layer = LAYER
	# Position is driven every frame from the mouse; nothing else in this scene
	# needs a process pass, so the visibility check below gates it.
	set_process(true)
	_repaint()


## Injected by [method HudRoot.compose] / [method HudRoot.rebind_player].
## Connects to the one signal and immediately reads the current value, so a
## mode armed before the bind still shows. Re-binding releases the previous
## connection first — a hot-seat handover (#459) hands over a different
## controller and must not leave the old one driving the badge.
func bind(input_ctl: PlayerInputController) -> void:
	_subs.release()
	_input_ctl = input_ctl
	if _input_ctl == null:
		_on_armed_icon_changed(null, Color.TRANSPARENT)
		return
	_subs.link(_input_ctl.armed_icon_changed, _on_armed_icon_changed)
	_on_armed_icon_changed(_input_ctl.get_armed_icon(), _input_ctl.get_armed_icon_tint())


func _on_armed_icon_changed(icon: Texture2D, tint: Color) -> void:
	_icon = icon
	_tint = tint
	_repaint()


## Hard-locked to the mouse position — no lag, no spring, no trailing. A
## trailing badge draws MORE peripheral attention while informing less, and an
## in-HUD Control already trails the hardware cursor by a frame at speed; adding
## more on top of that is the wrong direction.
##
## Never fades on idle and never appears only on movement: the player who forgot
## what is armed is precisely the one who stopped moving and looked down at the
## cursor. Visible whenever armed, unconditionally — and in particular NOT gated
## on whether the hovered node is a legal target. "Which mode am I in" and "is
## this a legal target" are different channels; this one answers the first.
func _process(_delta: float) -> void:
	if _badge == null or not _badge.visible:
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var mouse := viewport.get_mouse_position()
	# Hide when the pointer leaves the viewport — the badge describes a click
	# into the play area, and there is no such click to describe out there.
	var inside := Rect2(Vector2.ZERO, viewport.get_visible_rect().size).has_point(mouse)
	_badge.modulate.a = 1.0 if inside else 0.0
	_badge.position = mouse + OFFSET


## Lift the stored colour to [member glow_stops] and hand the pair to the rect.
##
## A null texture is the whole armed/unarmed switch: the badge is either showing
## a real glyph or is not in the frame at all. A transparent tint is a real,
## different case — "this level named no colour" — and modulates white rather
## than blanking, per [method ArmedMode.icon_tint].
func _repaint() -> void:
	if _texture_rect == null:
		return  # a `glow_stops` write before _ready(); _ready repaints.
	_texture_rect.texture = _icon
	_texture_rect.modulate = (
			Emissive.tint_peak(_tint, glow_stops) if _tint.a > 0.0 else Color.WHITE)
	_badge.visible = _icon != null
