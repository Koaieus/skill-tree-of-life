@tool
class_name OwnerPanel
extends FanPanel

## Tooltip V2 (#226/#228) — crown, FAR rung (entity-scoped). Mounted for every
## hover since #314 collapsed the occupancy-class variants into one `fan.tscn`,
## and gated by its own [method has_content] instead: there is no owner to
## render on an unallocated node. Pre-#314 the variant it was mounted in did
## that job, which is why this override didn't exist.
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

## Per-index reveal delay (fraction of the panel's own `progress`) — same
## staggered-reveal shape as [AddonsPanel] / [GrantedModifiersRoot].
const _ROW_STAGGER_STEP := 0.12
const _ROW_STAGGER_CAP := 0.85

@onready var _hostile_tag: Label = %HostileTag
@onready var _radar: AttributeRadar = %Radar

## The node currently rendered, if any (set by [method bind]).
var _bound_node: SkillNode = null

## One entry per rendered row, parallel to `_rows`' children — drives the
## staggered reveal from [method _apply_progress].
var _row_setters: Array[Callable] = []


func _ready() -> void:
	super._ready()
	# `_header.bind()` writes into an OWNED node's `Label.text` (a real,
	# serializable property) — per `.claude/rules/godot-workflow.md`'s @tool
	# _ready guard convention, skip all placeholder content in the editor.
	# The panel's size envelope comes from the [PanelLayout] skin's authored
	# `min_size` (the crown envelope), not from row count or header text, so
	# nothing is lost for in-editor placement/preview.
	if Engine.is_editor_hint():
		return
	_header.bind("Owner")


## Public entry point (#228). `_graph` is unused — this panel only ever
## reads the node's owning entity.
func bind(node: SkillNode, _graph: Graph) -> void:
	_bound_node = node
	_rebuild()


## False on an unallocated node: no owning entity, so nothing to disclose.
## This is the gate that used to be "which variant mounted me" (#314) — and it
## is what makes allocating a hovered node fan this panel OUT, since the same
## check is re-run when the node's ownership changes.
func has_content() -> bool:
	return _bound_node != null and _bound_node.owned_by != null


func _rebuild() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_row_setters.clear()
	var entity: Entity = _bound_node.owned_by if _bound_node != null else null
	if entity == null:
		_header.bind("Owner")
		_set_hostile(false)
		return
	_bind_header(entity)
	# This panel is the LOCAL PLAYER's HUD, not a generic per-viewer relation
	# test — "hostile" here means "not the player's faction". Real per-viewer
	# attitude (routing through Entity.attitude_to) needs a viewer entity
	# threaded through the fan's bind chain (FanPanel.bind(node, graph) ->
	# FanUnit -> TooltipFan._bind_content), which is deferred for the same
	# reason #384 deferred ally HUD color: at two teams with a single player
	# entity, viewer.attitude_to(owner) and faction_id != &"player" are
	# indistinguishable on screen. Revisit once a second player-side entity
	# ships.
	_set_hostile(entity.faction_id != &"player")
	_bind_radar_and_rows(entity)
	_apply_row_stagger()


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
		var value := 0.0
		if board != null:
			var stat := board.get_stat(id)
			if stat != null:
				value = float(stat.get_value())
		specs.append(AxisSpec.for_stat(id))
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
		_row_setters.append(row.set_progress)


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
