@tool
class_name FanPanel
extends Node2D
## Reusable circuit-fan tooltip panel (#223, epic #159). Wraps whatever skin
## Control is hand-placed as its first child — a [GlassPanel] or [HoloPanel]
## instance, authored in-scene like every other panel use in `ui/` — and
## forwards a single `glow` knob to it. Skin choice is "which packed scene is
## instanced as the child", per #215 — not a runtime enum FanPanel owns; swap
## it the same way you'd swap any other panel skin, by editing the child.
## See docs/domain/tooltip-fan.md.
##
## Since #303, FanPanel is a peer of [FanTrace]: it owns a readable [member
## progress] and self-driven [method play_in] / [method play_out], both
## returning a [Tween] to `await` — same contract, same scale+fade reveal it
## always rendered, just self-driven instead of puppeted by FanUnit.

## Normalized glow (0..1), forwarded per skin type: directly to [HoloPanel]'s
## own `glow`, or mapped onto [GlassPanel]'s `glow_color` alpha + `glow_strength`.
@export_range(0.0, 1.0, 0.01) var glow: float = 0.3:
	set(v):
		glow = v
		_push_glow()

## Tint used for [GlassPanel]'s glow_color when that's the active skin
## (HoloPanel has no separate tint — its glow is monochrome by design).
@export var glow_tint: Color = Color(0.55, 0.85, 1.0):
	set(v):
		glow_tint = v
		_push_glow()

## Scale the panel starts at when [member progress] is 0.
@export_range(0.5, 1.0, 0.01) var start_scale: float = 0.82

@export_group("Motion")
## Duration of the full unfurl tween ([member progress] 0 -> 1).
@export var panel_unfurl_duration := 0.22
## Duration of the full fade-out tween ([member progress] 1 -> 0) — scaled by
## how far this panel actually got before [method play_out] is called; see
## there for the floor.
@export var panel_fade_duration := 0.16

## 0 = hidden at [member start_scale], 1 = fully revealed. Assigning it
## re-applies the scale+fade reveal directly; [method play_in] / [method
## play_out] animate it via their own Tween.
@export_range(0.0, 1.0, 0.01) var progress := 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		_apply_progress()

var _lifecycle_tween: Tween = null


func _ready() -> void:
	_push_glow()
	if Engine.is_editor_hint():
		# Author-time: show the fully revealed panel so placement/skin is
		# witnessable while dragging. Pure visual setup, safe under @tool
		# (mirrors FanTrace's own editor-hint branch).
		progress = 1.0
		return
	# Runtime: start hidden; the coordinator/FanUnit calls play_in().
	progress = 0.0


# --- Content contract (#159 panel wave) ---------------------------------------

## Render `node`'s data into this panel. Base implementation is a deliberate
## no-op: a panel with static authored content (or a stub awaiting its content
## issue) needs nothing here. [TooltipFan] calls this on every FanPanel in the
## active variant, BEFORE any `play_in()`, so [method has_content] can be
## queried against real data.
##
## [param graph] is passed because two of the facts panels render — graph degree
## and entity degree ([method SkillNode.get_graph_degree] /
## [method SkillNode.get_entity_degree]) — need it, and a panel must NOT go
## hunting for it up the tree. The owning [Entity] is `node.owned_by`; it is
## null on an unowned node, which is the common case.
func bind(_node: SkillNode, _graph: Graph) -> void:
	pass


## Whether this panel has anything worth showing for the node it was last
## [method bind]ed to. Base implementation says yes — a panel only overrides
## this if it can legitimately be empty (no addons, no node-local stats, no
## owner, not a core).
##
## THIS IS THE FAN'S ONLY GATE since #314 collapsed the three occupancy-class
## variants into one `fan.tscn`. Every unit is mounted for every hover, so a
## panel that used to be filtered out by *not being in that variant* has to
## answer for itself here — see [OwnerPanel] and [CorePanel], which gained their
## overrides in that change.
##
## A panel answering `false` is suppressed by [TooltipFan]: its [FanUnit] stays
## HIDDEN, never plays in, and **gives up its clock pin** — [FanAnchorDriver]
## shares the arc out among the participating units only, so three live panels
## sit at 11/12/1 rather than at three of six slots with gaps between them.
##
## That reverses the pre-#314 rule, which held a suppressed panel's pin open so
## a present panel's trace landed in the same place regardless of its
## neighbours. The reversal is deliberate: a fan with a hole in it reads as "a
## panel failed to load", not as a deliberate omission, and positional constancy
## is not worth buying with that. Slot changes are eased rather than snapped
## ([member FanAnchorDriver.pin_slide_rate]), so a panel igniting mid-hover makes
## its neighbours slide over.
##
## Re-answered on every live update, not only on hover — allocating the node you
## are hovering is exactly the case this has to get right. The value is cached
## per unit in [member FanUnit.participating]; never read one without the other.
func has_content() -> bool:
	return true


## First Control child, whichever skin scene was hand-placed under this node.
func get_skin() -> Control:
	for child in get_children():
		if child is Control:
			return child
	return null


func _push_glow() -> void:
	var skin := get_skin()
	if skin == null:
		return
	if skin is HoloPanel:
		(skin as HoloPanel).glow = glow
	elif skin is GlassPanel:
		var panel := skin as GlassPanel
		panel.glow_strength = glow * 40.0
		panel.glow_color = Color(glow_tint.r, glow_tint.g, glow_tint.b, glow)


## Applies the current [member progress] as a cubic-ease-out scale
## (start_scale → 1.0) + fade (0 → 1) reveal.
func _apply_progress() -> void:
	var eased := _ease_out(progress)
	scale = Vector2.ONE * lerpf(start_scale, 1.0, eased)
	var m := modulate
	m.a = eased
	modulate = m


## Animates the panel unfurling itself in ([member progress] 0 → 1). Returns
## the Tween so a caller (FanUnit) can `await tween.finished` to sequence
## what comes next.
func play_in() -> Tween:
	_stop_lifecycle()
	_lifecycle_tween = create_tween()
	_lifecycle_tween.tween_property(self, "progress", 1.0, panel_unfurl_duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return _lifecycle_tween


## Animates the panel fading back out ([member progress] → 0). Scales its own
## duration by how far this panel actually got — a panel sitting at
## `progress == 0` (never opened) yields a near-zero leg, floored at ~0.03s so
## it still produces a frame instead of a hard cut; a panel at `progress ==
## 0.3` takes ~30% of [member panel_fade_duration]. Returns the Tween for
## sequencing.
func play_out() -> Tween:
	_stop_lifecycle()
	var duration := maxf(panel_fade_duration * progress, 0.03)
	_lifecycle_tween = create_tween()
	_lifecycle_tween.tween_property(self, "progress", 0.0, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	return _lifecycle_tween


func _stop_lifecycle() -> void:
	if _lifecycle_tween != null and _lifecycle_tween.is_valid():
		_lifecycle_tween.kill()
	_lifecycle_tween = null


static func _ease_out(t: float) -> float:
	var inv := 1.0 - t
	return 1.0 - inv * inv * inv
