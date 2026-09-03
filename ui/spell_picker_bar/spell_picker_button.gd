@tool
class_name SpellPickerButton
extends Button

## A single spell pick in [SpellPickerBar]. Toggle button (radio-managed by
## the bar's ButtonGroup) that renders a spell card:
##   * top inset — one tick per [member SpellDef.min_degree]
##   * icon (or letter glyph fallback)
##   * name + mana cost label
##
## Same shader scaffolding as [AttackModeButton] — the bg shader handles
## rounded-rect rendering, mouse-proximity glow, rim, breathing pulse when
## active, and a desaturated/dimmed disabled state; the text shader gives
## the name + letter labels a soft halo + tint blend. State plumbing routes
## hover / pressed (toggle) / disabled into shader strength uniforms via
## tweens so transitions are smooth.
##
## On hover emits [signal Events.spell_hovered] / [signal Events.spell_unhovered]
## so the floating [SpellTooltip] (mounted in HudRoot) shows a formatted scene
## with dynamic-value highlighting instead of a plain-text Godot tooltip.
##
## [b]Three independent gates (#743, #728).[/b] All three grey the same shader
## term, but only one flips the engine [member Button.disabled]:
##
## - [method set_actionable] — the bar-wide "your turn, AP left" gate. Genuinely
##   disabled: there is nothing to explain, the whole bar is already dimmed.
## - [method set_affordable] — mana (#743). Grey but CLICKABLE.
## - [method set_has_caster] — does any owned node clear the spell's min_degree
##   (#728). Grey but CLICKABLE.
##
## The last two stay clickable so a press can explain itself; a disabled Button
## swallows the very click their denial toast needs. [method set_actionable]
## replaced a `set_castable` that also carried min_degree — that term moved out
## when #728 removed the pre-picked source it was measured against, and became
## the bar-wide [method SpellBook.eligible_sources] question instead of a
## per-source one.
##
## [signal spell_picked] is the gated report of a press: [SpellPickerBar]
## connects to THAT, never to the raw [signal BaseButton.pressed], because two
## independent listeners on one native signal can't have one veto the other,
## and only this button knows whether its own press should count as a pick or
## a denial.

## Emitted on press when every clickable gate is met — the pick
## [SpellPickerBar] acts on. A press blocked by mana or by "no eligible caster"
## instead floats the matching denial (see [method _on_pressed]) and this does
## not fire.
signal spell_picked(spell: SpellDef)

const BG_SHADER := preload("res://ui/attack_mode_bar/attack_mode_button.gdshader")
const TEXT_SHADER := preload("res://ui/attack_mode_bar/attack_mode_button_text.gdshader")
const TICK_SCENE := preload("res://ui/spell_picker_bar/spell_picker_button_tick.tscn")

const ANIMATION_TIME: float = 0.2
const _LETTER_FONT_SIZE: int = 28

@export_color_no_alpha var tint: Color = Color(0.55, 0.85, 1.0)
@export_range(0.0, 1.0, 0.01) var glow_radius: float = 0.36

@export var spell: SpellDef = null:
	set(value):
		spell = value
		_apply_spell()

@onready var _bg: ColorRect = $Bg
@onready var _ticks: HBoxContainer = %Ticks
@onready var _icon_rect: TextureRect = %Icon
@onready var _name_label: Label = %NameLabel
@onready var _letter_label: Label = %LetterLabel
@onready var _float_anchor: Node2D = %FloatAnchor

var _bg_mat := ShaderMaterial.new()
var _text_mat := ShaderMaterial.new()
var _materials: Array[ShaderMaterial] = []

## The casting entity whose stats may modify spell values shown in the
## floating tooltip. Written only through [method set_caster].
var _caster: Entity = null

## Backing state for the three independent gates — see [method set_actionable]
## / [method set_affordable] / [method set_has_caster]. All start true so a
## freshly-instantiated button (before its bar's first gating pass) reads as
## pickable rather than flashing grey for a frame.
var _actionable: bool = true
var _affordable: bool = true
var _has_caster: bool = true

var _hover_tweener: Tween
var _active_tweener: Tween
var _disabled_tweener: Tween


var hovered: float = 0.0:
	set(value):
		hovered = value
		_push(&"glow_strength", value)

var active: float = 0.0:
	set(value):
		active = value
		_push(&"active_strength", value)

var _disabled_strength: float = 0.0:
	set(value):
		_disabled_strength = value
		_push(&"disabled_strength", value)


func _ready() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(96, 96)
	clip_text = true
	_install_materials()
	_push(&"tint", tint)
	_push(&"glow_radius", glow_radius)
	_push(&"texture_size", Vector2i(maxi(1, int(size.x)), maxi(1, int(size.y))))
	# Snap state — Button's pressed/disabled may have been set in the .tscn
	# before we wired the shader.
	hovered = 0.0
	active = 1.0 if button_pressed else 0.0
	_disabled_strength = 1.0 if disabled else 0.0
	_apply_spell()


func _install_materials() -> void:
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = BG_SHADER
	_bg.material = _bg_mat
	_text_mat = ShaderMaterial.new()
	_text_mat.shader = TEXT_SHADER
	_name_label.material = _text_mat
	_letter_label.material = _text_mat
	_materials = [_bg_mat, _text_mat]


func _push(param: StringName, value: Variant) -> void:
	for mat in _materials:
		mat.set_shader_parameter(param, value)


## Toggle the bar-wide act gate (not your turn / out of AP) — flips
## [member Button.disabled] so engine click-gating + the shader's disabled fade
## both engage. The one gate that stays unclickable: the bar is dimmed whole
## and a per-spell toast would explain nothing the player can act on.
func set_actionable(actionable: bool) -> void:
	_actionable = actionable
	disabled = not actionable
	_refresh_grey()


## Toggle affordability (mana, #743) — greys the SAME shader term as
## [method set_castable] but leaves [member Button.disabled] alone, so a press
## still lands: [method _on_pressed] reads [member _affordable] to decide
## between forwarding [signal spell_picked] and floating the "can't afford"
## denial. Deliberately NOT folded into `disabled` — see this file's top
## docstring and #743's acceptance spec (a disabled Button swallows the click
## the denial toast needs).
func set_affordable(affordable: bool) -> void:
	_affordable = affordable
	_refresh_grey()
	_refresh_toggle_mode()


## Toggle "some owned node can cast this at all" (#728) — min_degree against the
## attacker's whole territory rather than against one pre-picked source, since
## there is no longer a source to pick. Grey but clickable, exactly like
## [method set_affordable]: the press is what earns the `spell_denied_no_caster`
## toast, and the two dead ends are deliberately different words — no caster is
## fixed by growing territory, no mana by waiting.
##
## Its sibling dead end — casters exist but nothing is in reach — gets NO toast
## by the owner's 2026-09-03 ruling: that is the ordinary ranged-attack read
## ("here is my reach, nothing hostile is in it"), and the union's drawn reach
## is what says so.
func set_has_caster(has_caster: bool) -> void:
	_has_caster = has_caster
	_refresh_grey()
	_refresh_toggle_mode()


## Tell the bar's selection state onto this button (replaces a bare
## [method set_pressed_no_signal] call so [method _refresh_toggle_mode] always
## re-runs after a selection change — see its docstring for why a stale
## `toggle_mode` is the failure mode that skips this).
func set_selected(selected: bool) -> void:
	set_pressed_no_signal(selected)
	_refresh_toggle_mode()


## The greyed presentation is one shader term shared by all three gates —
## greyed iff ANY is unmet. Only [method set_actionable] touches `disabled`.
func _refresh_grey() -> void:
	_tween_disabled(0.0 if (_actionable and _affordable and _has_caster) else 1.0)


## Godot's [ButtonGroup] exclusivity (un-press the sibling, commit
## `button_pressed` on the clicked one) runs synchronously as part of native
## click processing, BEFORE any `pressed`/`toggled` handler gets a chance to
## veto it — so an unaffordable-but-toggle_mode-true button would steal the
## highlight from the real selection on click, with nothing to hand it back
## to (nothing re-drives [SpellPickerBar.sync_selected] unless the selected
## spell itself actually changes, which an unaffordable press deliberately
## does not do).
##
## Fix: while unaffordable (or, #728, with no eligible caster — same shape,
## same reason), turn [member toggle_mode] off instead. A
## non-toggle Button still emits [signal BaseButton.pressed] on click (so
## [method _on_pressed] still runs and the denial still floats) but never
## touches `button_pressed` or the group — nothing to steal, nothing to
## revert.
##
## The `button_pressed` term keeps the CURRENTLY SELECTED button toggle-capable
## even while unaffordable (mana drops on OTHER casts below this spell's cost
## while it's still the active selection): its highlight must survive, and
## re-clicking an already-selected-but-unaffordable spell is a legitimate
## "why can't I recast this" moment that should re-float the denial, not
## silently no-op. Called after every affordability change AND every toggled
## transition (native group-driven unpress included) — see [method _on_toggled]
## and [method set_selected] — so a stale `true` can't survive a deselect.
func _refresh_toggle_mode() -> void:
	toggle_mode = button_pressed or (_affordable and _has_caster)


## Tell the button which entity is hovering-as-caster, so [SpellTooltip] can
## read that board for the values the caster's stats move off the printed base.
## Purely presentational — it never gates the button, which
## [method set_actionable] / [method set_affordable] / [method set_has_caster]
## own.
func set_caster(caster: Entity) -> void:
	_caster = caster


func refresh() -> void:
	_apply_spell()


func _apply_spell() -> void:
	if not is_node_ready():
		return
	if spell == null:
		_name_label.text = ""
		_icon_rect.texture = null
		_letter_label.text = ""
		if not Engine.is_editor_hint():
			_clear_ticks()
		return
	_name_label.text = "%s (%d)" % [spell.name, spell.mana_cost]
	if spell.icon != null:
		_icon_rect.texture = spell.icon
		_letter_label.visible = false
	else:
		_icon_rect.texture = null
		_letter_label.visible = true
		_letter_label.text = spell.name.substr(0, 1).to_upper() if spell.name != "" else "?"
	_rebuild_ticks(spell.min_degree)


func _clear_ticks() -> void:
	for c in _ticks.get_children():
		c.queue_free()


func _rebuild_ticks(n: int) -> void:
	_clear_ticks()
	for i in maxi(0, n):
		var tick := TICK_SCENE.instantiate() as ColorRect
		_ticks.add_child(tick)


func _tooltip_for(s: SpellDef) -> String:
	var lines: Array[String] = []
	lines.append("%s — %d mana" % [s.name, s.mana_cost])
	lines.append("Requires node degree ≥ %d" % s.min_degree)
	if s.description != "":
		lines.append(s.description)
	if s.propagation != null:
		var prop := s.propagation.get_description()
		if prop != "":
			lines.append(prop)
	return "\n".join(lines)


# --- Shader plumbing -------------------------------------------------------

func _process(_delta: float) -> void:
	if _bg == null:
		return
	_push(&"mouse_uv", get_local_mouse_position() / size)


func _on_resized() -> void:
	_push(&"texture_size", Vector2i(maxi(1, int(size.x)), maxi(1, int(size.y))))


func _on_mouse_entered() -> void:
	_tween_hover(1.0)
	if spell != null:
		Events.spell_hovered.emit(spell, _caster)


func _on_mouse_exited() -> void:
	_tween_hover(0.0)
	Events.spell_unhovered.emit()


func _on_toggled(toggled_on: bool) -> void:
	_tween_active(1.0 if toggled_on else 0.0)
	# Catches the native-unpress case: the ButtonGroup just cleared
	# button_pressed on this button (another spell got picked), which by
	# itself leaves `toggle_mode` stale-true if this one is unaffordable —
	# see [method _refresh_toggle_mode]'s docstring.
	_refresh_toggle_mode()


## The single affordability gate (#743). Connected to the native
## [signal BaseButton.pressed] in the scene — every click "lands" here first,
## whether the mana gate lets it through or not; see this file's top
## docstring for why [SpellPickerBar] cannot do this check by itself.
func _on_pressed() -> void:
	# Structural before resource: "no node of yours can cast this" outranks
	# "you can't afford it right now", because it's the one the player cannot
	# fix by waiting a turn.
	if not _has_caster:
		Events.ui_action_denied.emit(_float_anchor, "spell_denied_no_caster")
		return
	if not _affordable:
		Events.ui_action_denied.emit(_float_anchor, "spell_denied_no_mana")
		return
	spell_picked.emit(spell)


func _tween_hover(to: float) -> void:
	if _hover_tweener: _hover_tweener.kill()
	_hover_tweener = create_tween()
	_hover_tweener.tween_property(self, "hovered", to, ANIMATION_TIME)


func _tween_active(to: float) -> void:
	if _active_tweener: _active_tweener.kill()
	_active_tweener = create_tween()
	_active_tweener.tween_property(self, "active", to, ANIMATION_TIME)


func _tween_disabled(to: float) -> void:
	if _disabled_tweener: _disabled_tweener.kill()
	_disabled_tweener = create_tween()
	_disabled_tweener.tween_property(self, "_disabled_strength", to, ANIMATION_TIME)
