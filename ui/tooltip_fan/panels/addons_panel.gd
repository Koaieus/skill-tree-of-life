@tool
class_name AddonsPanel
extends FanPanel

## Tooltip V2 (#226/#229) — crown, NEAR rung (node-scoped), right by default.
## Capped at 3 items + a "+N more" tail (fixed envelope, unlike the two
## growing crown panels).
##
## Data source is [method SkillNode.get_addons] directly — NOT [method
## SkillNode.get_addon_tooltip_sections], which is a filtered view that drops
## any addon contributing neither modifiers nor a description (Bunker,
## Fortification, Clamp all render nothing through it). That silent drop was
## the bug this panel exists to fix, so every addon on the node gets a row.
##
## One [AddonItem] per addon: title + modifiers + description all render
## together, in that order — never either/or. An addon with neither modifiers
## nor a description still renders as a named item; presence is itself the
## information.
##
## [method has_content] suppresses the whole unit when the node carries no
## addons — the common case — so the fan never shows an empty bordered box.

const _CAP := 3

const _ADDON_ITEM_SCENE: PackedScene = preload("res://ui/tooltip_fan/addon_item.tscn")

## Per-index reveal delay (fraction of the panel's own `progress`), same
## staggered-reveal shape as [GrantedModifiersRoot]'s `_row_setters` /
## `_apply_row_stagger` — read-only reference, not shared code, since that
## file belongs to another in-flight unit.
const _ROW_STAGGER_STEP := 0.12
const _ROW_STAGGER_CAP := 0.85

@onready var _header: PanelHeader = %Header
@onready var _rows: VBoxContainer = %Rows

## The node last [method bind]ed, if any — read by [method has_content].
var _bound_node: SkillNode = null

## One entry per rendered [AddonItem] (or the overflow label), parallel to
## `_rows`' children — drives the staggered reveal from [method _apply_progress].
var _row_setters: Array[Callable] = []


func _ready() -> void:
	super._ready()
	# See owner_panel.gd's _ready for why this skips in-editor entirely.
	if Engine.is_editor_hint():
		return
	_header.bind("Addons")


func bind(node: SkillNode, _graph: Graph) -> void:
	_bound_node = node
	_rebuild_rows()
	_apply_row_stagger()


## Empty when the node carries no addons — the common case. Suppresses the
## whole unit (see [method FanPanel.has_content]'s doc) rather than showing a
## bordered box with nothing in it.
func has_content() -> bool:
	return _bound_node != null and not _bound_node.get_addons().is_empty()


func _rebuild_rows() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_row_setters.clear()
	if _bound_node == null:
		return

	var addons := _bound_node.get_addons()
	var shown_count := mini(addons.size(), _CAP)
	for i in shown_count:
		_add_addon_item(addons[i])

	var overflow := addons.size() - shown_count
	if overflow > 0:
		_add_overflow_label(overflow)


func _add_addon_item(addon: SkillNodeAddon) -> void:
	var item := _ADDON_ITEM_SCENE.instantiate() as AddonItem
	_rows.add_child(item)
	# 4th arg = addon icon (#281 — the icon lives on the addon, mirrored from
	# SpellDef; null falls back to AddonItem's placeholder).
	item.bind(addon.get_tooltip_title(), addon.get_tooltip_modifiers(), addon.description, addon.icon)
	_row_setters.append(item.set_progress)


func _add_overflow_label(overflow: int) -> void:
	var label := Label.new()
	label.text = "+%d more" % overflow
	label.modulate = Color(0.55, 0.55, 0.6)
	label.add_theme_font_size_override("font_size", 10)
	_rows.add_child(label)
	_row_setters.append(func(t: float) -> void: _apply_control_reveal(label, t))


## Mirrors [AddonItem.set_progress]'s own scale+fade so the hand-rolled
## overflow [Label] reveals the same way the real items do.
func _apply_control_reveal(control: Control, t: float) -> void:
	var eased := _ease_out(clampf(t, 0.0, 1.0))
	control.scale = Vector2.ONE * lerpf(0.92, 1.0, eased)
	var m := control.modulate
	m.a = eased
	control.modulate = m


## Overrides [FanPanel._apply_progress] to also drive each row's own staggered
## reveal off this panel's shared `progress` — the base implementation only
## scales/fades the panel as a whole, which would otherwise pop every
## AddonItem in at full opacity the instant the panel starts revealing.
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
