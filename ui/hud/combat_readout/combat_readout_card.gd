@tool
class_name CombatReadoutCard
extends MarginContainer
## Base for the four Combat Readout cards (#112: Melee/Ranged/Magic/Defense).
## Owns only the shared "am I the selected mode" visual language — border
## glow when active, dimmed when not, transient un-mute on a stat change even
## while dimmed (design's "un-mute even if not selected" behavior). Per-mode
## value binding lives in each subclass script.
##
## Root is a MarginContainer (margin 0) so its reported minimum size is the
## max of its children's — specifically the "Padded" inner MarginContainer
## wrapping Content. A plain Control root reports (0,0) regardless of its
## children's real size, which collapsed every card to zero height inside
## the shell's VBoxContainer. GlassPanel is a sibling of Padded at the same
## 0-margin level so it fills the exact same rect as the card, behind it.

const DIM_OPACITY := 0.55
const FLASH_TIME := 0.35

@export var mode_color: Color = Color(0.9, 0.75, 0.4, 1.0)

@onready var _panel: GlassPanel = %GlassPanel

var _active: bool = false
var _flash_tween: Tween

## #119 — node-local stat override preview. Set by [CombatReadout] off
## Events.skill_node_hovered/unhovered; only a node owned by [member
## _owner_entity] can preview (see [method _local_override_or_null]).
var _hover_node: SkillNode = null
var _owner_entity: Entity = null


func _ready() -> void:
	_apply_active(false)


## Called by [CombatReadout] on hover/unhover. Subclasses override
## [method _refresh] (already their per-mode convention) to react.
func set_hover_node(node: SkillNode) -> void:
	_hover_node = node
	_refresh()


## Virtual — subclasses already define this per their bind()'d stats.
func _refresh() -> void:
	pass


## Returns the node-local combined value for `stat_id` if [member _hover_node]
## is currently previewable AND its value differs from `baseline` — null
## otherwise (not owned by us, no hover, or the node doesn't override it).
## Callers pass the result straight to [method CombatValueRow.show_override]
## / [method CombatValueRow.clear_override].
func _local_override_or_null(stat_id: StringName, baseline: float) -> Variant:
	if _hover_node == null or _owner_entity == null:
		return null
	if _hover_node.owned_by != _owner_entity:
		return null
	var overridden: float = float(_hover_node.get_local_value(stat_id))
	return overridden if overridden != baseline else null


## Called by [CombatReadout] (the shell) when the selected attack mode
## changes. Cards that aren't mode-bound (Defense) never receive true.
func set_active(active: bool) -> void:
	_active = active
	_apply_active(active)


func _apply_active(active: bool) -> void:
	if _panel != null:
		_panel.border_color = mode_color if active else Color(0.47, 0.55, 0.75, 0.16)
		_panel.glow_color = Color(mode_color.r, mode_color.g, mode_color.b, 0.5 if active else 0.0)
		_panel.glow_strength = 18.0 if active else 0.0
	modulate.a = 1.0 if active else DIM_OPACITY


## Briefly un-mutes a non-selected card so a stat change is still noticed —
## does not flip [member _active] or change the border, just the opacity.
func flash_unmute() -> void:
	if _active:
		return
	if _flash_tween != null:
		_flash_tween.kill()
	modulate.a = 1.0
	_flash_tween = create_tween()
	_flash_tween.tween_interval(0.6)
	_flash_tween.tween_property(self, ^"modulate:a", DIM_OPACITY, FLASH_TIME)
