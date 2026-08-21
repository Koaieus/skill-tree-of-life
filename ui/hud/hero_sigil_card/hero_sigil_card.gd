@tool
class_name HeroSigilCard
extends MarginContainer

## Left column, top card (#108): class emblem (spinning ring + glyph), level
## badge, entity name + class subtitle, Health/Mana as [PoolGauge]s with
## dimmed "+N/t" regen captions. Also the floater-anchor origin for
## entity/core stat-change toasts (closes #91) — see [member float_anchor]
## and [method GameRoot]'s wiring of [FloaterDirector.player_anchor].
##
## [b]XP is no longer this card's business (#320).[/b] The gauge, its "+N XP"
## chip and the whole level-replay state machine moved to [XpTrack], the
## top-center strip. `XPRow` survives here only as hidden scenery — deliberately
## kept rather than deleted while the new placement settles, and deliberately
## unbound: a second binder on the same `xp` pool would run its own sequencer and
## emit a second `level_reached`, which [AnnouncementLayer]'s coalescing would
## absorb into one banner stamped "LEVEL UP ×2" for a single level.
## The level badge stays — [HudRoot] drives it from [signal XpTrack.level_reached]
## via [method show_level], so badge, banner and bar all beat together.
##
## Root is a 0-margin MarginContainer (not a plain Control) so its reported
## minimum size aggregates its children's — a plain Control reports (0,0)
## regardless of content, which collapsed this card to zero height inside
## HudRoot's LeftColumnSlot VBoxContainer. See combat_readout_card.gd for
## the same pattern/writeup (shared bug across all HUD cards).

@onready var _panel: GlassPanel = %GlassPanel
@onready var _emblem_ring: EmblemRing = %EmblemRing
@onready var _emblem_glyph: Label = %EmblemGlyph
@onready var _sigil_glyph: SigilGlyph = %SigilGlyph
@onready var _level_badge: Label = %LevelBadge
@onready var _name_label: Label = %NameLabel
@onready var _class_label: Label = %ClassLabel
@onready var _health_gauge: PoolGauge = %HealthGauge
@onready var _health_caption: Label = %HealthCaption
@onready var _mana_gauge: PoolGauge = %ManaGauge
@onready var _mana_caption: Label = %ManaCaption

## World/UI-space anchor floaters rise from (stat gains, wounds, level-ups).
## A plain [Node2D] child works as a [FloaterRequest.target] unmodified —
## CanvasItem global transforms compose across the Control/Node2D boundary,
## so this resolves to screen pixels exactly like the Control it sits in.
@onready var float_anchor: Node2D = %FloatAnchor

## Radians/sec the emblem ring spins. Time-uniform driven (not gated to
## runtime-only) so it animates in the editor too, per the @tool contract.
@export_range(0.0, 2.0, 0.01) var emblem_spin_speed: float = 0.35

var _entity: Entity
## The level the badge is currently showing. Driven by [XpTrack]'s gauge beats
## (via [method show_level]), not by the model — `stat_board.level` is already
## final while the XP bar is still replaying the cascade that got there.
var _shown_level: int = 1

## Everything this card connects to the CURRENT hero's pools, released as a
## unit when `bind` re-points at a different hero (#459 hot-seat handover).
var _binds := BindScope.new()


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if _emblem_ring != null:
		_emblem_ring.rotation += delta * emblem_spin_speed


func bind(entity: Entity) -> void:
	_binds.release()
	_entity = entity
	# Above the null check on purpose: null is a real argument here (level
	# teardown, or a handover to nobody), and letting go of the hero has to let
	# go of their colour too — otherwise the departed hero's tint stays on the
	# emblem.
	_apply_entity_tint(_entity.color if _entity != null else Color(0, 0, 0, 0))
	if _entity == null:
		return

	_name_label.text = _entity.display_name
	_class_label.text = _entity.core_class.display_name if _entity.core_class != null else "Allround"
	var sigil: Sigil = _entity.core_class.sigil if _entity.core_class != null else null
	_sigil_glyph.sigil = sigil
	_sigil_glyph.visible = sigil != null
	_emblem_glyph.visible = sigil == null  # fallback glyph for classes with no sigil authored
	show_level(_entity.level)

	var board := _entity.stat_board
	if board == null:
		return
	# `core_healing` is health's per-turn companion (D-25) — same "incoming next
	# turn" band mana and XP already render, which is exactly why D-25 chose an
	# integer heal over a sub-1 sliver: zero new UI.
	_bind_pool(_health_gauge, _health_caption, board.health, board.core_healing)
	_bind_pool(_mana_gauge, _mana_caption, board.mana, board.mana_per_turn)


## Paint the whole portrait — ring, sigil, fallback glyph — in the bound hero's
## [member Entity.color], which is what makes the card read as *this* hero's in
## a hot-seat handover (#459). A zero-alpha `tint` means "nobody bound" and
## every mark returns to its authored fallback.
##
## Identity arrives here as plain LDR sRGB; each mark decides its own emissive
## tier (the ring lifts to VALUE, the sigil stays at its authored weight), so no
## caller ever hand-picks an HDR float. See `.claude/rules/hdr-color.md`.
func _apply_entity_tint(tint: Color) -> void:
	if _emblem_ring != null:
		_emblem_ring.entity_tint = tint
	if _sigil_glyph != null:
		_sigil_glyph.entity_tint = tint
	if _emblem_glyph != null:
		if tint.a > 0.0:
			_emblem_glyph.add_theme_color_override(&"font_color", Emissive.tint(tint, Emissive.VALUE))
		else:
			_emblem_glyph.remove_theme_color_override(&"font_color")


## Set the level shown on the emblem badge. Wired by [HudRoot] to
## [signal XpTrack.level_reached] so the badge bumps on the gauge's beat rather
## than the instant the model levelled.
func show_level(level: int) -> void:
	_shown_level = level
	if _level_badge != null:
		_level_badge.text = str(_shown_level)


## #504: every gauge follows its pool directly. The `health` pool used to need
## an [Entity] alongside it, to read a `shown_health` view field that lagged the
## model; under design B the pool itself moves on the beat clock, so one path
## serves health and mana alike.
func _bind_pool(gauge: PoolGauge, caption: Label, pool: PoolStat, per_turn: ScalarStat) -> void:
	if gauge == null or pool == null:
		return
	gauge.min_value = 0.0
	gauge.max_value = float(pool.value)
	gauge.current = float(pool.current)
	gauge.preview_gain = float(per_turn.value) if per_turn != null else 0.0
	# Tweened, not hard-cut (#317) — and `animate_to` deliberately only tweens
	# *gains*, so a wound still snaps down and leaves its drain trail behind.
	var animate := func():
		gauge.animate_to(float(pool.current), float(pool.value))
	_binds.link(pool.current_changed, animate.unbind(1))
	_binds.link(pool.value_changed, animate)
	if per_turn != null:
		_binds.link(per_turn.value_changed, func(): gauge.preview_gain = float(per_turn.value))
	if caption != null:
		var refresh_caption := func():
			var cur: float = float(pool.current)
			if per_turn != null and float(per_turn.value) > 0.0:
				caption.text = "%d/%d (+%d/t)" % [int(cur), int(pool.value), int(per_turn.value)]
			else:
				caption.text = "%d/%d" % [int(cur), int(pool.value)]
		_binds.link(pool.current_changed, refresh_caption.unbind(1))
		_binds.link(pool.value_changed, refresh_caption)
		if per_turn != null:
			_binds.link(per_turn.value_changed, refresh_caption)
		refresh_caption.call()
