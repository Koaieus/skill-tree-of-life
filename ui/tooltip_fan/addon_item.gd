@tool
class_name AddonItem
extends VBoxContainer

## Icon + addon title + modifier rows + description, in that order — each part
## INDEPENDENTLY COLLAPSIBLE. Shared row component for Tooltip V2 (epic #159,
## #293), consumed by #229's ADDONS panel. See docs/domain/tooltip-fan.md.
##
## Per #229's hardening decisions:
##   - title + icon are ALWAYS shown
##   - modifier rows hide (as a block) when there are none
##   - the description hides when empty
##   - an addon with neither modifiers nor description still renders as a
##     named item — presence is itself the information
##
## Modifier rows reuse [ModSlabRow] (#221) rather than re-implementing its
## per-operator formatting/tint — one [ModSlabRow] per [StatModifier], stat
## names resolved via `StatRegistry`, mirroring `skill_node_tooltip.gd`'s
## `StatRegistry.get_def(m.stat_id).display_name` pattern.
##
## Icon uses a placeholder texture until #281 lands. Per
## `.claude/rules/godot-workflow.md`, a bare [PlaceholderTexture2D] collapses
## a Sprite/TextureRect's UVs and breaks any UV-reading shader hosted later —
## so the placeholder here is a real (tiny, flat-color) [GradientTexture2D],
## authored as a scene sub-resource, not a PlaceholderTexture2D.
##
## Reveal is driven externally via [method set_progress] against the shared
## fixed-clock / `progress(0..1)` contract — this node owns no Tween.

const _MOD_SLAB_ROW_SCENE := preload("res://ui/tooltip_fan/mod_slab_row.tscn")

## Scale the item starts at when [method set_progress]'s `t` is 0.
@export_range(0.5, 1.0, 0.01) var start_scale: float = 0.92

@onready var _icon: TextureRect = %Icon
@onready var _title_label: Label = %TitleLabel
@onready var _modifier_rows: VBoxContainer = %ModifierRows
@onready var _description_label: Label = %DescriptionLabel


## Binds this item's title, modifier rows (one [ModSlabRow] per modifier,
## empty array hides the block entirely), optional description, and optional
## icon override (falls back to the built-in placeholder texture).
func bind(title: String, modifiers: Array[StatModifier], description: String = "", icon: Texture2D = null) -> void:
	_title_label.text = title
	if icon != null:
		_icon.texture = icon

	for child in _modifier_rows.get_children():
		_modifier_rows.remove_child(child)
		child.queue_free()
	for m in modifiers:
		var def := StatRegistry.get_def(m.stat_id)
		var stat_name := def.display_name if def != null else String(m.stat_id)
		var row := _MOD_SLAB_ROW_SCENE.instantiate()
		_modifier_rows.add_child(row)
		row.bind(m, stat_name)
	_modifier_rows.visible = not modifiers.is_empty()

	_description_label.text = description
	_description_label.visible = not description.is_empty()


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
