@tool
class_name AttributesPanel
extends Control
## Left column, second card (#109): [AttributeRadar] + numeric attribute
## rows + hover tooltip (shared [AttributeRules] text) + Senses row
## (vision/sensor). Reads [StatDef.tint_color] — no second palette.
##
## Root stays a plain Control (not a Container) because [member Tooltip] is
## a free-floating absolute-positioned overlay — a Container parent would
## force it into the layout flow instead. A plain Control's default
## [method _get_minimum_size] ignores children entirely (returns
## [member custom_minimum_size], i.e. (0,0) here), which collapsed this
## card to zero height inside HudRoot's LeftColumnSlot VBoxContainer; the
## override below forwards the real minimum size from "Margin" (the actual
## layout content) without pulling Tooltip into container management. See
## combat_readout_card.gd for the sibling fix used where there's no
## overlay child to worry about.

## Order pins Constitution to spoke index 3, the hexagon's bottom vertex
## (AttributeRadar's angle(i) = -90deg + i*60deg for n=6 axes) — not row
## display order, which stays scene-tree order in the .tscn.
const ATTR_IDS: Array[StringName] = [
	&"strength", &"dexterity", &"intelligence", &"constitution", &"wisdom", &"perception",
]

@onready var _margin: MarginContainer = %Margin
@onready var _radar: AttributeRadar = %AttributeRadar
@onready var _rows: Array[AttributeRow] = [
	%StrengthRow, %DexterityRow, %IntelligenceRow, %ConstitutionRow, %WisdomRow, %PerceptionRow,
]
@onready var _tooltip: PanelContainer = %Tooltip
@onready var _tooltip_label: Label = %TooltipLabel
@onready var _vision_value: Label = %VisionValue
@onready var _sensor_value: Label = %SensorValue

var _board: StatBoard


## Forwards the real layout content's minimum size so this Control reports
## correctly to a Container parent (HudRoot's LeftColumnSlot). Reads the
## node directly rather than the cached @onready [member _margin] — this can
## fire before this node's own _ready() during the parent's layout pass.
func _get_minimum_size() -> Vector2:
	var margin := get_node_or_null(^"%Margin") as MarginContainer
	return margin.get_combined_minimum_size() if margin != null else Vector2.ZERO


## What this panel connects to the CURRENT hero's board, released as a unit
## when [method bind] re-points (#459 hot-seat handover).
var _binds := BindScope.new()


func _ready() -> void:
	_tooltip.visible = false
	# Re-poll the forwarded minimum size whenever the wrapped content's
	# changes (e.g. a value gaining a digit) — Container parents only
	# re-layout on this Control's own minimum_size_changed, which the
	# _get_minimum_size() override alone won't trigger.
	_margin.minimum_size_changed.connect(update_minimum_size)
	for row in _rows:
		row.row_hovered.connect(_on_row_hovered)
		row.row_unhovered.connect(_on_row_unhovered)
	_radar.axis_hovered.connect(func(i): _on_row_hovered(ATTR_IDS[i] if i < ATTR_IDS.size() else &""))
	_radar.axis_unhovered.connect(func(): _tooltip.visible = false)


func bind(board: StatBoard) -> void:
	_binds.release()
	_board = board
	if _board == null:
		return

	var stats: Array[ScalarStat] = [
		_board.strength, _board.dexterity, _board.intelligence, _board.constitution,
		_board.wisdom, _board.perception,
	]
	var specs: Array[AxisSpec] = []
	for i in _rows.size():
		var id := ATTR_IDS[i]
		var def := StatRegistry.get_def(id)
		if def != null:
			_rows[i].attr_label = def.display_name
			_rows[i].tint_color = def.tint_color
		_rows[i].attr_id = id
		specs.append(AxisSpec.for_stat(id))
	_radar.configure(specs)

	for i in _rows.size():
		var stat := stats[i]
		if stat == null:
			continue
		_binds.link(stat.value_changed, _refresh.bind(i, stat))
		_refresh(i, stat)

	if _board.vision_range != null:
		_binds.link(_board.vision_range.value_changed, _refresh_senses)
	if _board.sensor_range != null:
		_binds.link(_board.sensor_range.value_changed, _refresh_senses)
	_refresh_senses()


## Rebinding used to be a no-op stub on the assumption that board swaps were
## dev-only; hot-seat coop (#459) makes them a per-turn event, and every row +
## both sense readouts stayed wired to the previous hero. [member _binds] is
## the release — see [BindScope].



func _refresh(i: int, stat: ScalarStat) -> void:
	var v := float(stat.value)
	_rows[i].set_value(v)
	_radar.set_value(i, v)


func _refresh_senses() -> void:
	if _board == null:
		return
	if _vision_value != null and _board.vision_range != null:
		_vision_value.text = "%d px" % int(_board.vision_range.value)
	if _sensor_value != null and _board.sensor_range != null:
		_sensor_value.text = "%d hops" % int(_board.sensor_range.value)


func _on_row_hovered(attr_id: StringName) -> void:
	if _board == null or attr_id == &"":
		return
	var lines := AttributeRules.describe(attr_id, _board)
	if lines.is_empty():
		_tooltip.visible = false
		return
	_tooltip_label.text = "\n".join(lines)
	_tooltip.visible = true


func _on_row_unhovered(_attr_id: StringName) -> void:
	_tooltip.visible = false
