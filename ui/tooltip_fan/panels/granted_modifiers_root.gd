@tool
class_name GrantedModifiersRoot
extends Node2D

## Tooltip V2 (#226/#227) — the ROOTS: the modifier stack BELOW the node
## (Decision 1 of the swarmable spec v2). Deliberately NOT a [FanPanel]: it
## has "no containing panel" by design — a stack of small slabs, unbounded
## height, growing downward into uncontested space. So it does not go through
## [FanAnchor]'s box-edge derivation at all (Decision 4 only applies to
## panel-shaped things); its own trace (if any) is a plain vertical trunk.
##
## Still a fan-tier "component": self-animating, `play_in()`/`play_out() ->
## Tween`, a readable `progress`, driven by the coordinator ([TooltipFan])
## exactly like a [FanUnit] — [method play_in]/[method play_out] are the
## duck-typed contract the coordinator fires uniformly across everything in
## the `fan_unit` group, not just literal FanUnit instances.
##
## [method bind] renders real content: one [ModSlabRow] per flattened
## modifier leaf (#305/#221), plus a "Grants <spell>" line per granted
## [SpellGrant] (a bare [SlabRow] tinted keystone gold, sorted ABOVE the
## modifier slabs — a granted spell is the bigger fact about the node, and
## a slab is the same reading surface #588 gave every other content row).
## This is a BOONS list, not a "modifiers" list — one grammar, no header, no
## legend, no frame (see the issue's chrome decisions). No separate
## addon-modifier traversal: addon `entity_modifiers` already land in
## [member SkillNode.modifiers] via [method SkillNode._on_addon_added], so
## flattening that one array is enough.
##
## Deliberately EXEMPT from the fan's [method FanPanel.has_content]
## suppression contract — see [method _add_empty_row]. A node with nothing to
## show renders one muted "no modifiers" row instead of vanishing: this root
## is the common hover's primary readout, unbounded and un-boxed, and an
## absence here would read as a broken tooltip rather than a clean omission.
## Do not add `has_content()` to this file.

@export_range(0.5, 1.0, 0.01) var start_scale: float = 0.9

## Scale each row starts at (matches [member ModSlabRow.start_scale]'s
## default) — used for the hand-rolled empty-state row, which isn't a
## [SlabRow]/[ModSlabRow] instance and so doesn't get that knob for free.
@export_range(0.5, 1.0, 0.01) var row_start_scale: float = 0.92

## 0 = fully hidden (used to gate visibility only; individual rows fade via
## the shared `set_progress(t)` contract like every other content row).
var progress: float = 0.0

var _tween: Tween = null

## The node currently rendered, if any (set by [method bind]).
var _bound_node: SkillNode = null

## Per-row reveal setters, in display order (spell-grant lines first, then
## one per flattened modifier leaf) — parallel to `_rows`' children. A
## [SlabRow]/[ModSlabRow] hands over its own `set_progress` directly; the
## hand-rolled empty-state [Label] gets a bound closure over
## [method _apply_control_reveal] instead.
var _row_setters: Array[Callable] = []

const _MOD_SLAB_SCENE: PackedScene = preload("res://ui/tooltip_fan/mod_slab_row.tscn")
const _SLAB_ROW_SCENE: PackedScene = preload("res://ui/tooltip_fan/slab_row.tscn")

## Keystone gold — matches [CorePanel]'s "deliberate gold skin" tone. Granted
## spells read as a keystone-tier fact, never as an ordinary stat operator.
const _KEYSTONE_GOLD := Color(0.98, 0.767, 0.127, 1.0)

## Muted tone for the "no modifiers" empty-state row — deliberately lower
## contrast than every other row here (spell grants are gold, modifier slabs
## carry their stat's tint): this line reports an absence, not a boon, and
## must read as quieter than the content it stands in for.
const _EMPTY_MUTED := Color(0.55, 0.58, 0.65)

## Wording for the empty state (#227 follow-up). Lowercase, sentence-register,
## matching the boons-list grammar (`+4 Intelligence`, `Grants Spark`) rather
## than a shouty header — this stack has no header at all by design.
const _EMPTY_TEXT := "no modifiers"

## Per-index reveal delay, expressed as a fraction of the shared `progress`
## range (0..1) — there is no per-row delay knob, so this component owns the
## stagger. Capped so even a long stack's last row keeps enough span left to
## reach full reveal by `progress == 1`.
const _ROW_STAGGER_STEP := 0.12
const _ROW_STAGGER_CAP := 0.85

@onready var _rows: VBoxContainer = %Rows


func _ready() -> void:
	# Scoped to the EDITED scene, not the process-wide hint (#685): skip
	# populating rows for a node that's part of a scene someone has open for
	# editing (consistent with the stub FanPanel subclasses — the root's own
	# size is content-driven by design, unbounded and growing downward, so an
	# empty %Rows during editor load doesn't hide any authored envelope). But
	# a throwaway instance the tooltip-fan live sandbox tab spawns
	# (`fan_live_sandbox.tscn` via `fan.tscn`'s Roots child) is NOT part of
	# anyone's edited scene, so it still needs `progress` reset here — a
	# blanket `Engine.is_editor_hint()` skip silently left it unconfigured
	# there. See `VfxEditorScene.is_edited` and docs/domain/sandbox-framework.md.
	if VfxEditorScene.is_edited(self):
		return
	progress = 0.0
	_apply_progress()
	visible = false


## Public entry point (#227). Renders `node`'s granted boons: spell-grant
## lines (from [method SkillNode.get_node_effects], keystone gold) above one
## [ModSlabRow] per flattened modifier leaf (from `node.modifiers` via
## [method StatModifier.flatten_all] — addon-granted modifiers included for
## free). Rebuilds from scratch every call; a null `node` clears the stack.
func bind(node: SkillNode) -> void:
	_bound_node = node
	_rebuild_rows()
	_apply_progress()


func _rebuild_rows() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_row_setters.clear()
	if _bound_node == null:
		return
	for effect in _bound_node.get_node_effects():
		if effect is SpellGrant and effect.spell_def != null:
			_add_spell_line(effect.spell_def)
	for m in StatModifier.flatten_all(_bound_node.modifiers):
		_add_mod_row(m)
	if _row_setters.is_empty():
		_add_empty_row()


func _add_spell_line(spell_def: SpellDef) -> void:
	var row := _SLAB_ROW_SCENE.instantiate() as SlabRow
	_rows.add_child(row)
	row.bind_text("Grants %s" % spell_def.name, _KEYSTONE_GOLD)
	_row_setters.append(row.set_progress)


## Empty state (#227 follow-up): a node with no granted spells and no
## modifier leaves renders one muted row rather than an invisible stack — see
## this class's own doc comment for why suppression (the [FanPanel] contract)
## is wrong here. Goes through the same `_row_setters` stagger as every other
## row, so it fades in and reverses on interrupt like any content row; it is
## not special-cased outside that mechanism.
func _add_empty_row() -> void:
	var label := Label.new()
	label.text = _EMPTY_TEXT
	label.modulate = _EMPTY_MUTED
	# SHRINK_CENTER, not a CENTER text alignment: the label is narrower than
	# `%Rows`' box, so under the container default (FILL) it stretched across
	# the box and drew its text flush LEFT — ~20px off the SkillNode this
	# stack hangs under. Centering text inside a full-width box would have
	# worked too; centering the box itself is the smaller claim.
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_rows.add_child(label)
	_row_setters.append(func(t: float) -> void: _apply_control_reveal(label, t))


func _add_mod_row(m: StatModifier) -> void:
	var row := _MOD_SLAB_SCENE.instantiate() as ModSlabRow
	_rows.add_child(row)
	row.bind(m)
	_row_setters.append(row.set_progress)


## Reveal for the hand-rolled empty-state [Label] — mirrors
## [method ModSlabRow.set_progress] (scale + fade, cubic ease-out) since a
## bare Label doesn't have that contract of its own.
func _apply_control_reveal(control: Control, t: float) -> void:
	var eased := _ease_out(clampf(t, 0.0, 1.0))
	control.scale = Vector2.ONE * lerpf(row_start_scale, 1.0, eased)
	var m := control.modulate
	m.a = eased
	control.modulate = m


func _apply_progress() -> void:
	var eased := _ease_out(clampf(progress, 0.0, 1.0))
	scale = Vector2.ONE * lerpf(start_scale, 1.0, eased)
	var m := modulate
	m.a = eased
	modulate = m
	_apply_row_stagger()


## Remaps the shared `progress` (0..1) into each row's own 0..1 via a
## per-index delay — see `_ROW_STAGGER_STEP`'s doc. Rows past the delay
## window ease from 0 the same as the root does; rows still in it sit at 0.
func _apply_row_stagger() -> void:
	for i in _row_setters.size():
		var delay := clampf(i * _ROW_STAGGER_STEP, 0.0, _ROW_STAGGER_CAP)
		var span := 1.0 - delay
		var row_t := clampf((progress - delay) / span, 0.0, 1.0) if span > 0.0 else progress
		_row_setters[i].call(row_t)


## Self-animating IN, matching the component contract [FanTrace]/[FanPanel]
## expose post-#303: returns the [Tween] so the coordinator can `await` it.
func play_in() -> Tween:
	visible = true
	_kill_tween()
	_tween = create_tween()
	_tween.tween_method(_set_progress, progress, 1.0, 0.2) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return _tween


## Self-animating OUT. Scales the reverse duration by how far this root
## actually got (`progress`), same rule the components apply — a root that
## never rose above 0 retracts in (near) zero time rather than eyeball parity.
func play_out() -> Tween:
	_kill_tween()
	var duration: float = maxf(0.2 * progress, 0.03)
	_tween = create_tween()
	_tween.tween_method(_set_progress, progress, 0.0, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func() -> void: visible = false)
	return _tween


func enter_hidden() -> void:
	_kill_tween()
	progress = 0.0
	_apply_progress()
	visible = false


func _set_progress(t: float) -> void:
	progress = t
	_apply_progress()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


static func _ease_out(t: float) -> float:
	var inv := 1.0 - t
	return 1.0 - inv * inv * inv
