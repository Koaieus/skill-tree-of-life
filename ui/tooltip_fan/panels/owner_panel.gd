@tool
class_name OwnerPanel
extends FanPanel

## Tooltip V2 (#226/#228) — crown, FAR rung (entity-scoped). Only mounted by
## the `owned`/`owned_core` variants (#226 Decision 2), which is exactly when
## `node.owned_by` is non-null — so unlike [NodeStatsPanel] this panel needs
## no [method has_content] override.
##
## [method bind] renders: [PanelHeader] (all-caps owner name, "Lv N  Class"
## subtext), the HOSTILE OWNER tag (this panel's, NOT the ID chip's — #232
## must not duplicate it; meaningful whenever the owner isn't the player
## faction), an [AttributeRadar] (#219), then one [StatValueRow] per curated
## attribute.
##
## The curated attribute set is a fixed, explicit, authored list — NOT an
## enumeration of the entity's board (see [constant _ATTRIBUTE_IDS]). Two
## reasons (settled on #228, the #269 CON-hexagon catch): the panel must stay
## fixed-height for the crown envelope (#226), and enemies keep some secrets —
## full stat disclosure on hover is declined deliberately. A stat landing on
## the entity board later changes NOTHING here. The radar's spoke count
## derives from this array's size, so the panel stays correct whether the
## list is five entries or six.
##
## No scale concept on the radar (attribute bands diverge, e.g. WIS in the
## hundreds beside STR in the tens) — tracked separately as #273, not this
## panel's problem.

## Explicit authored attribute set — mirrors `ui/hud/attributes_panel/attributes_panel.gd`'s
## `ATTR_IDS` precedent. Deliberately NOT derived from the board.
const _ATTRIBUTE_IDS: Array[StringName] = [
	&"strength", &"dexterity", &"intelligence", &"wisdom", &"perception",
]

const _STAT_VALUE_ROW_SCENE: PackedScene = preload("res://ui/tooltip_fan/stat_value_row.tscn")

@onready var _header: PanelHeader = %Header
@onready var _hostile_tag: Label = %HostileTag
@onready var _radar: AttributeRadar = %Radar
@onready var _rows: VBoxContainer = %Rows

## The node currently rendered, if any (set by [method bind]).
var _bound_node: SkillNode = null


func _ready() -> void:
	super._ready()
	# `_header.bind()` writes into an OWNED node's `Label.text` (a real,
	# serializable property) — per `.claude/rules/godot-workflow.md`'s @tool
	# _ready guard convention, skip all placeholder content in the editor.
	# The panel's size envelope comes from the authored HoloPanel/Content
	# rects, not from row count or header text, so nothing is lost for
	# in-editor placement/preview.
	if Engine.is_editor_hint():
		return
	_header.bind("Owner")


## Public entry point (#228). `_graph` is unused — this panel only ever
## reads the node's owning entity.
func bind(node: SkillNode, _graph: Graph) -> void:
	_bound_node = node
	_rebuild()


func _rebuild() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var entity: Entity = _bound_node.owned_by if _bound_node != null else null
	if entity == null:
		_header.bind("Owner")
		_set_hostile(false)
		return
	_bind_header(entity)
	_set_hostile(entity.faction != &"player")
	_bind_radar_and_rows(entity)


func _bind_header(entity: Entity) -> void:
	var class_name_text := ""
	if entity.core_class != null:
		class_name_text = entity.core_class.display_name
	var subheader := "Lv %d  %s" % [entity.level, class_name_text] if not class_name_text.is_empty() else "Lv %d" % entity.level
	_header.bind(entity.display_name, subheader)


func _set_hostile(hostile: bool) -> void:
	if _hostile_tag == null:
		return
	_hostile_tag.visible = hostile
	if hostile:
		_hostile_tag.text = "HOSTILE OWNER"


func _bind_radar_and_rows(entity: Entity) -> void:
	var board: StatBoard = entity.stat_board
	var specs: Array[AxisSpec] = []
	var defs: Array[StatDef] = []
	var values: Array[float] = []
	for id in _ATTRIBUTE_IDS:
		var def: StatDef = StatRegistry.get_def(id)
		var axis_label: String = String(id).substr(0, 3).to_upper()
		var axis_color := Color.WHITE
		var value := 0.0
		if def != null:
			axis_label = def.display_name.substr(0, 3).to_upper()
			axis_color = def.tint_color
		if board != null:
			var stat := board.get_stat(id)
			if stat != null:
				value = float(stat.get_value())
		specs.append(AxisSpec.new(axis_label, axis_color))
		defs.append(def)
		values.append(value)
	if _radar != null:
		_radar.configure(specs)
		for i in values.size():
			_radar.set_value(i, values[i])
	for i in _ATTRIBUTE_IDS.size():
		var def := defs[i]
		if def == null:
			continue
		var row := _STAT_VALUE_ROW_SCENE.instantiate() as StatValueRow
		_rows.add_child(row)
		row.bind_scalar(def, values[i])
		row.set_progress(1.0)
