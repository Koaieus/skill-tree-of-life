@tool
class_name CorePanel
extends FanPanel

## Tooltip V2 (#226/#231) — crown, FAR rung (entity-scoped), CORE nodes only
## (`owned_core.tscn` mounts this unit; no other variant does). Envelope sized
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
## No [method has_content] override: this unit only mounts in `owned_core.tscn`,
## which is only instanced for a hovered node that IS the entity's core — the
## suppression contract exists for panels that can be empty on a node they DO
## mount for, which never applies here.

const _ENVELOPE_ROWS := 12

@onready var _header: PanelHeader = %Header
@onready var _rows: VBoxContainer = %Rows

const _MOD_SLAB_SCENE: PackedScene = preload("res://ui/tooltip_fan/mod_slab_row.tscn")
const _STAT_VALUE_ROW_SCENE: PackedScene = preload("res://ui/tooltip_fan/stat_value_row.tscn")

## The node currently rendered, if any (set by [method bind]).
var _bound_node: SkillNode = null


func _ready() -> void:
	super._ready()
	# See owner_panel.gd's _ready for why this skips in-editor entirely
	# (header text is a real serializable property, not just ownerless rows).
	if Engine.is_editor_hint():
		return


## Public entry point (#231). `node` is expected to be this entity's core —
## `owned_core.tscn` (the only variant mounting this unit) is only instanced
## for a hover that already satisfies that, so no `is_core()` re-check here.
func bind(node: SkillNode, _graph: Graph) -> void:
	_bound_node = node
	_rebuild_rows()


func _rebuild_rows() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
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
	row.set_progress(1.0)


func _add_mod_row(m: StatModifier) -> void:
	if m.formula != null:
		_add_scaling_row(m)
		return
	var row := _MOD_SLAB_SCENE.instantiate() as ModSlabRow
	_rows.add_child(row)
	row.bind(m)


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
