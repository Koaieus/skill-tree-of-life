class_name CrucibleReadout
extends VBoxContainer

## The crucible's right-hand readout, always on: the spell's name, one line of
## shape (targeting · reach), its base behaviour, then one
## [CrucibleReadoutLine] per [method ReadoutLines.lines] entry — socketed
## aspects top to bottom in socket order, then innate-only ones. Holding
## `ui_more_info` (or [member force_more_info]) adds the full
## [SpellSections] below.
##
## Owns its hover state: [method set_hovered_socket] lights and expands that
## socket's line; [method preview_wedge] reads every line as if a wheel wedge
## were socketed (the plan's own [method MagicAttackPlan.socket_order_with]).
## [method line_anchor] is where a body routes a socket's trace; re-read it on
## [signal anchors_changed].
##
## Binds to a bare [MagicAttackPlan] and repaints on its own
## [signal AttackPlan.state_changed] — a host only calls [method bind].

## The lines moved or were rebuilt: every [method line_anchor] may have changed.
signal anchors_changed

const _MORE_INFO_ACTION := &"ui_more_info"
const _LINE_SCENE := preload("res://ui/hud/command_tray/bodies/crucible_readout_line.tscn")

## Holds the more-info expansion open without the action — for a sandbox tab
## or a test with no keyboard to read.
@export var force_more_info := false:
	set(value):
		force_more_info = value
		_poll_more_info()

@onready var _name: Label = %Name
@onready var _shape: Label = %Shape
@onready var _base: Label = %Base
@onready var _lines: VBoxContainer = %Lines
@onready var _sections_box: Container = %Sections
@onready var _sections: Array[SpellTooltipSection] = [
	%CastSection, %OnArrivalSection, %ThenSection, %CritsSection]

var _plan: MagicAttackPlan = null
var _hovered_socket := -1
var _preview_socket := -1
var _preview_id: StringName = &""
var _more_info := false
## What the shown lines were built from — a repaint that would draw the same
## thing (a target hover fires state_changed too) keeps the nodes.
var _shown_key := ""
var _header_spell: SpellDef = null
var _header_source: SkillNode = null
var _sections_built := false


func _ready() -> void:
	_lines.sort_children.connect(anchors_changed.emit)
	item_rect_changed.connect(anchors_changed.emit)
	_sections_box.visible = false
	_refresh()


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		_poll_more_info()


## Read [param plan]; null unbinds. Re-binding the bound plan is free.
func bind(plan: MagicAttackPlan) -> void:
	if plan == _plan:
		return
	if _plan != null and _plan.state_changed.is_connected(_refresh):
		_plan.state_changed.disconnect(_refresh)
	_plan = plan
	if _plan != null:
		_plan.state_changed.connect(_refresh)
	_preview_socket = -1
	_preview_id = &""
	_refresh()


## Light and expand socket [param socket]'s line; −1 clears.
func set_hovered_socket(socket: int) -> void:
	if socket == _hovered_socket:
		return
	_hovered_socket = socket
	_apply_focus()


func hovered_socket() -> int:
	return _hovered_socket


## Read every line as if [param aspect_id] sat in socket [param socket] — the
## hovered wheel wedge — and light that line. The plan is untouched.
func preview_wedge(socket: int, aspect_id: StringName) -> void:
	if socket == _preview_socket and aspect_id == _preview_id:
		return
	_preview_socket = socket
	_preview_id = aspect_id
	_refresh()


## Back to the plan as configured.
func clear_preview() -> void:
	preview_wedge(-1, &"")


## Whether the full sections are showing.
func is_more_info() -> bool:
	return _more_info


func name_text() -> String:
	return _name.text if _name != null else ""


## The line nodes, top to bottom.
func line_nodes() -> Array[CrucibleReadoutLine]:
	var out: Array[CrucibleReadoutLine] = []
	if _lines == null:
		return out
	for child in _lines.get_children():
		if child is CrucibleReadoutLine and not child.is_queued_for_deletion():
			out.append(child)
	return out


## Where socket [param socket]'s trace lands: the left edge, vertical middle,
## of its line's first row, in this readout's local coordinates (read from the
## laid-out rects, so valid once the container has sorted). [constant
## Vector2.INF] when no line is fed by that socket.
func line_anchor(socket: int) -> Vector2:
	for node in line_nodes():
		if node.socket() == socket:
			var local := get_global_transform().affine_inverse() * node.get_global_transform()
			return local * Vector2(0.0, node.first_row_height() * 0.5)
	return Vector2.INF


func _refresh() -> void:
	if not is_node_ready():
		return
	var spell := _plan.spell if _plan != null else null
	var board := _plan.attacker.stat_board if _plan != null and _plan.attacker != null else null
	var source := _plan.source if _plan != null else null
	_refresh_header(spell, board, source)
	var previewing := _plan != null and _preview_socket >= 0 and not _preview_id.is_empty()
	var lines: Array[ReadoutLines.ReadoutLine] = []
	if previewing:
		lines = ReadoutLines.preview(_plan, _preview_socket, _preview_id)
	else:
		lines = ReadoutLines.lines(_plan)
	var key := _key_of(spell, lines)
	if key != _shown_key:
		_shown_key = key
		_rebuild_lines(lines, spell, board)
	_apply_focus()


func _refresh_header(spell: SpellDef, board: StatBoard, source: SkillNode) -> void:
	if spell == _header_spell and source == _header_source and not _name.text.is_empty():
		return
	_header_spell = spell
	_header_source = source
	_sections_built = false
	_name.text = spell.name if spell != null else ""
	var built := SpellSections.build(spell, board, source)
	_shape.text = " · ".join(built.cast.lines)
	var base: PackedStringArray = []
	if spell != null:
		for effect in spell.on_hit_effects:
			if effect != null:
				base.append(effect.get_description(spell, board, source))
	_base.text = " ".join(base)
	_base.visible = not _base.text.is_empty()
	if _more_info:
		_build_sections()


func _rebuild_lines(lines: Array[ReadoutLines.ReadoutLine], spell: SpellDef,
		board: StatBoard) -> void:
	for child in _lines.get_children():
		_lines.remove_child(child)
		child.queue_free()
	for line in lines:
		var node: CrucibleReadoutLine = _LINE_SCENE.instantiate()
		_lines.add_child(node)
		node.bind(line, spell, board)
	anchors_changed.emit()


## The previewed socket's line wins over the hovered one.
func _apply_focus() -> void:
	var focus := _preview_socket if _preview_socket >= 0 and not _preview_id.is_empty() \
			else _hovered_socket
	for node in line_nodes():
		var on := focus >= 0 and node.socket() == focus
		node.set_highlighted(on)
		node.set_expanded(on)


func _poll_more_info() -> void:
	if not is_node_ready():
		return
	var held := force_more_info or Input.is_action_pressed(_MORE_INFO_ACTION)
	if held == _more_info:
		return
	_more_info = held
	if _more_info:
		_build_sections()
	_sections_box.visible = _more_info


func _build_sections() -> void:
	if _sections_built:
		return
	_sections_built = true
	var board := _plan.attacker.stat_board if _plan != null and _plan.attacker != null else null
	var built := SpellSections.build(_header_spell, board, _header_source)
	var lines: Array[SpellSections.Lines] = [built.cast, built.on_arrival, built.then, built.crits]
	for i in _sections.size():
		_sections[i].bind(lines[i].lines, lines[i].dynamic)


static func _key_of(spell: SpellDef, lines: Array[ReadoutLines.ReadoutLine]) -> String:
	var parts: PackedStringArray = [String(spell.id) if spell != null else ""]
	for line in lines:
		parts.append("%d|%s|%d" % [line.socket, line.text(), line.points])
	return "\n".join(parts)
