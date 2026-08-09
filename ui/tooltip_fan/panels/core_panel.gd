@tool
class_name CorePanel
extends FanPanel

## Tooltip V2 (#226/#231) — crown, FAR rung (entity-scoped), CORE nodes only,
## enforced by this panel's own [method has_content] since #314 (before that,
## being mounted solely by `owned_core.tscn` was the gate). Envelope sized
## to the worst case per the "Crown envelope inputs" issue comment: 8
## modifier leaves (`pacifist_core.tres`) + 1 core-HP row = 9, with headroom
## to 12 rows. Deliberate gold skin exception — a [GlassPanel] child with
## [member FanPanel.glow_tint] set gold in-scene (there is no separate gold
## skin scene; the two skins are [GlassPanel]/[HoloPanel] and this is the
## fan's one intentional non-default choice) — because the core is the
## entity's identity and must not read as just another readout.
##
## [method bind] renders: PanelHeader as the core class's `display_name`, core
## HP as a numeric [StatValueRow] (never a bar, matching #230's convention),
## then one row per flattened leaf of `entity.core_class.modifiers`, in
## authored order (#183 composites — e.g. `ninja_core.tres`'s budget pack —
## flatten to one row per leaf, never one opaque row). A formula-driven leaf
## (per-level class bonuses, `value` is just the coefficient) does NOT render
## through [method StatModifier.format] — reading `core_class.modifiers`
## directly means it's never bound to a board, so `get_effective_value()`
## falls back to the bare coefficient and a naive `format()` call would print
## a misleading flat "+1" for what is actually a per-level scaling bonus.
## Instead it renders the coefficient plus an explicit "(scales)" suffix so it
## can never be mistaken for a flat bonus. Swaps to `StatFormula.description`
## verbatim once that field lands on `StatFormula` (separate issue, not on
## master yet) — not blocked on it, behind one small helper.
##
## [method has_content] answers false unless the hovered node IS a core. That
## used to be guaranteed structurally — `owned_core.tscn` was the only variant
## mounting this unit — but #314 mounts every unit for every hover, so the
## condition has to be stated rather than assumed.

const _ENVELOPE_ROWS := 12


const _MOD_SLAB_SCENE: PackedScene = preload("res://ui/tooltip_fan/mod_slab_row.tscn")
const _STAT_VALUE_ROW_SCENE: PackedScene = preload("res://ui/tooltip_fan/stat_value_row.tscn")

## Per-index reveal delay (fraction of the panel's own `progress`) — same
## staggered-reveal shape as [AddonsPanel] / [GrantedModifiersRoot].
const _ROW_STAGGER_STEP := 0.12
const _ROW_STAGGER_CAP := 0.85

## The node currently rendered, if any (set by [method bind]).
var _bound_node: SkillNode = null

## One entry per rendered row, parallel to `_rows`' children — drives the
## staggered reveal from [method _apply_progress].
var _row_setters: Array[Callable] = []


func _ready() -> void:
	super._ready()
	# See owner_panel.gd's _ready for why this skips in-editor entirely
	# (header text is a real serializable property, not just ownerless rows).
	if Engine.is_editor_hint():
		return


## Public entry point (#231). Binds unconditionally; whether the panel is shown
## at all is [method has_content]'s call.
func bind(node: SkillNode, _graph: Graph) -> void:
	_bound_node = node
	_rebuild_rows()
	_apply_row_stagger()


## False unless the hovered node is its entity's core — see the class doc for
## why this is an explicit check rather than a structural guarantee.
func has_content() -> bool:
	return _bound_node != null and _bound_node.is_core()


func _rebuild_rows() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_row_setters.clear()
	if _bound_node == null:
		return
	var entity: Entity = _bound_node.owned_by
	if entity == null or entity.core_class == null:
		_header.bind("Core")
		return
	_header.bind(entity.core_class.display_name if not entity.core_class.display_name.is_empty() else "Core")
	_add_core_hp_row(entity)
	for m in StatModifier.flatten_all(entity.core_class.modifiers):
		_add_mod_row(m)


func _add_core_hp_row(entity: Entity) -> void:
	if entity.stat_board == null or entity.stat_board.health == null:
		return
	var def: StatDef = StatRegistry.get_def(&"health")
	if def == null:
		return
	var health := entity.stat_board.health
	var row := _STAT_VALUE_ROW_SCENE.instantiate() as StatValueRow
	_rows.add_child(row)
	row.bind_pool(def, health.current, health.value)
	_row_setters.append(row.set_progress)


func _add_mod_row(m: StatModifier) -> void:
	if m.formula != null:
		_add_scaling_row(m)
		return
	var row := _MOD_SLAB_SCENE.instantiate() as ModSlabRow
	_rows.add_child(row)
	row.bind(m)
	# `ModSlabRow._ready` parks itself at progress 0 — invisible — because its
	# rest state is "the caller drives the reveal" (#221 §4). Registering the
	# setter is what un-parks it; `_apply_row_stagger` then drives it.
	_row_setters.append(row.set_progress)


## Formula-bound leaf, rendered as coefficient + "(scales)" per #231's
## formula-rendering addendum — see this class's own doc comment for why
## [method StatModifier.format] is wrong here.
func _add_scaling_row(m: StatModifier) -> void:
	var label := Label.new()
	var def: StatDef = StatRegistry.get_def(m.stat_id)
	var name: String = String(m.stat_id)
	var tint := Color.WHITE
	if def != null:
		name = def.modifier_name if not def.modifier_name.is_empty() else def.display_name
		tint = def.tint_color
	label.text = "%+d %s (scales)" % [roundi(m.value), name]
	label.add_theme_color_override("font_color", tint)
	_rows.add_child(label)
	_row_setters.append(func(t: float) -> void: _apply_control_reveal(label, t))


## Mirrors [method ModSlabRow.set_progress] (scale + fade, cubic ease-out)
## since a bare [Label] doesn't have that contract of its own.
func _apply_control_reveal(control: Control, t: float) -> void:
	var eased := _ease_out(clampf(t, 0.0, 1.0))
	control.scale = Vector2.ONE * lerpf(0.92, 1.0, eased)
	var m := control.modulate
	m.a = eased
	control.modulate = m


## Overrides [FanPanel._apply_progress] to also drive each row's own staggered
## reveal off this panel's shared `progress` — the base implementation only
## scales/fades the panel as a whole, which would otherwise pop every row in
## at full opacity the instant the panel starts revealing.
func _apply_progress() -> void:
	super._apply_progress()
	_apply_row_stagger()


func _apply_row_stagger() -> void:
	for i in _row_setters.size():
		var delay := clampf(i * _ROW_STAGGER_STEP, 0.0, _ROW_STAGGER_CAP)
		var span := 1.0 - delay
		var row_t := clampf((progress - delay) / span, 0.0, 1.0) if span > 0.0 else progress
		_row_setters[i].call(row_t)


static func _ease_out(t: float) -> float:
	var inv := 1.0 - t
	return 1.0 - inv * inv * inv
