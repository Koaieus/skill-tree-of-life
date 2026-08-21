@tool
class_name CombatReadoutCard
extends Control
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

@export_range(0.0, 1.0, 0.01) var dim_opacity := 0.72
@export_range(0.0, 1.0, 0.01) var flash_time := 0.35
@export_range(0.0, 1.0, 0.01) var glow_strength := 0.07

@export var _board: StatBoard

## #390 — GlassPanel's `border_color`/`glow_color` sit inside the HUD's
## bloom-included canvas layer, so this is a "panel border" case the tier
## vocabulary covers same as text: VALUE for the selected-mode border.
@export var mode_color: Color = Emissive.at(Color(0.9, 0.75, 0.4), Emissive.VALUE)


@export var _active: bool = false:
	set(v):
		if v != _active:
			_active = v
			_apply_active(v)

@export_placeholder('Panel Title') var title: String = "Panel Title":
	set = set_title


var _flash_tween: Tween

## #119 — node-local stat override preview. Set by [CombatReadout] off
## Events.skill_node_hovered/unhovered; only a node owned by [member
## _owner_entity] can preview (see [method _local_override_or_null]).
var _hover_node: SkillNode = null
var _owner_entity: Entity = null

## Everything `_bind` connects to the CURRENT hero's board, released as a unit
## when this card is re-pointed at a different one (#459 hot-seat handover).
## Subclasses route their stat subscriptions through it — see [method _bind].
var _binds := BindScope.new()


@onready var _title_label: Label = %Title
@onready var _panel: GlassPanel = %GlassPanel


func set_title(v: String) -> void:
		title = v
		if _title_label:
			_title_label.text = title

func _ready() -> void:
	set_title(title)
	if Engine.is_editor_hint():
		return
	_apply_active(false)


## Called by [CombatReadout] on hover/unhover. Subclasses override
## [method _refresh] (already their per-mode convention) to react.
func set_hover_node(node: SkillNode) -> void:
	_hover_node = node
	_refresh()

## Bind this card to an entity so it can start listening for stat changes.
## The board is always [member Entity.stat_board] — a card previews that
## entity's node-local overrides, so a board from anywhere else would make
## [method _local_override_or_null] compare against a foreign baseline.
## Virtual hook `_bind()` can be overridden in concrete classes to set up bindings
func bind(owner_entity: Entity) -> void:
	_binds.release()
	_owner_entity = owner_entity
	var board: StatBoard = owner_entity.stat_board if owner_entity != null else null
	_board = board
	if board == null:
		return
	# Call subclass-overridable hook, board and entity guaranteed to exist
	_bind(board, owner_entity)
	_refresh()

## Virtual — called by `bind()` when entity/stat_board are checked; to set up
## the real wiring between panel and stat board. Connect through
## [member _binds] (`_binds.link(sig, cb)`), never `sig.connect` directly, or
## the previous hero's stats keep driving this card after a handover.
@warning_ignore("unused_parameter")
func _bind(board: StatBoard, owner_entity: Entity = null) -> void:
	return
	
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
		_panel.border_color = mode_color if active else Emissive.at(Color(0.47, 0.55, 0.75, 0.16), Emissive.INERT)
		_panel.border_width = 1.8 if active else 1.0
		_panel.glow_color = Color(mode_color.r, mode_color.g, mode_color.b, glow_strength if active else 0.0)
		_panel.glow_strength = glow_strength if active else 0.0
	modulate.a = 1.0 if active else dim_opacity


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
	_flash_tween.tween_property(self, ^"modulate:a", dim_opacity, flash_time)
