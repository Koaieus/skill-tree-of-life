@tool
class_name MagicBody
extends CommandTrayBodyBase
## Magic tab content: the crucible (#1585). The vessel (%SpellButton, the
## equipped spell full-bleed at [member vessel_px], an [ArcaneCircle] turning
## behind it) on the left, its [InfusionSockets] fanned on an arc hugging its
## bottom edge, a circuit trace from each filled socket down, then right into
## its own line of the always-on [CrucibleReadout] in the middle, and Launch
## bottom-right. The traces are [method CrucibleTraces.route] over the laid-out
## rects: socket 0 sits rightmost ([member InfusionSockets.right_to_left]) and
## the readout lists its line topmost, so they nest without crossing.
##
## The readout owns its hover, wheel-preview and Shift state; the body only
## forwards socket hovers and wheel-wedge hovers to it. The readout scrolls
## inside %ReadoutScroll, so its Shift expansion never grows the tray.
##
## [b]The picker floats (#1485).[/b] The body shows the equipped spell as one
## collapsed %SpellButton; pressing it toggles [SpellPickMode] on the seat's
## [ArmedStack] ([method MagicMode.toggle_picker]). The spell bar lives in
## %PickerPanel, a `top_level` panel whose bottom edge sits
## [member picker_gap_px] above the body's top edge and which grows upward over
## the graph. It is outside the body's layout, so it adds nothing to the body's
## combined minimum size, shown or hidden. The STACK decides its visibility —
## shown iff a [SpellPickMode] is on the branch — so the body keeps no
## open/closed state of its own, and every close (a pick, a hotkey, a graph
## click, right-click, a launch) hides it for free.
##
## [b]The spell bar is bounded, not merely wide (#753).[/b] A [Control] is
## clamped UP to its combined minimum size, so a row of N fixed 96px buttons
## used to set this body's min width — and the spellbook grows through loot
## without bound, which is what shoved the whole tray out from under its slot.
## The fix is two-part and both halves are load-bearing: [SpellPickerBar] is an
## [HFlowContainer] (min width = ONE button, overflow wraps to rows), and the
## rows past [constant MAX_VISIBLE_ROWS] live inside %SpellScroll rather than
## growing this body further. So a 20-spell book costs exactly the same width
## and height as a 3-spell one that already wrapped.
##
## %SpellScroll uses [constant ScrollContainer.SCROLL_MODE_RESERVE], NOT
## `AUTO`. Under `AUTO` the scrollbar only takes its 8px once it appears, which
## narrows the bar by 8px at the exact moment content overflows — and a
## narrower [HFlowContainer] can wrap to one MORE row, so a book that needs two
## rows can land on three and start scrolling a row early. It converges (the
## bar only ever gets narrower) rather than oscillating, but it means the row
## count is not a pure function of the spell count. `RESERVE` keeps the gutter
## reserved whether or not the bar is shown, which makes the layout a
## single-pass fixed point for 8px of permanent width. Verified against 4.7.1:
## inner width is 292/292 under RESERVE where AUTO gives 300/292.

## How many wrapped rows of spell buttons the body shows before %SpellScroll
## starts scrolling instead of growing. Owner call (2026-09-04): "the entire
## Body is to be ~180px, so stacking two rows of 96px elements offers like
## negative margins.. maybe 80px is still fine" — hence two rows, and
## [constant SpellPickerBar.COMPACT_BUTTON_PX] once a second row exists.
const MAX_VISIBLE_ROWS: int = 2

## Gap between %PickerPanel's bottom edge and the body's top edge.
@export_range(0, 32, 1, "suffix:px") var picker_gap_px: int = 4:
	set(v):
		picker_gap_px = v
		_place_picker()

## %PickerPanel's width. Not the body's full width: the bar's row count is a
## function of its width, and at ~880px a 20-spell book packs into exactly
## [constant MAX_VISIBLE_ROWS] compact rows and stops scrolling.
@export_range(200, 900, 1, "suffix:px") var picker_width_px: int = 640:
	set(v):
		picker_width_px = v
		_place_picker()

## Edge of the vessel, the equipped spell's tile. Tentative.
@export_range(48, 200, 1, "suffix:px") var vessel_px: int = 112:
	set(v):
		vessel_px = v
		_apply_vessel()

## How far the socket arc tucks up beside the vessel's lower corners. Tentative.
@export_range(0, 120, 1, "suffix:px") var arc_tuck_px: int = 40:
	set(v):
		arc_tuck_px = v
		_apply_vessel()

## Vertical offset between adjacent traces' turns under the arc. Tentative.
@export_range(2, 32, 1, "suffix:px") var trace_turn_step_px: int = 8:
	set(v):
		trace_turn_step_px = v
		_queue_traces()

## Gap between the rightmost riser and the readout's left edge. Tentative.
@export_range(0, 64, 1, "suffix:px") var trace_riser_gap_px: int = 10:
	set(v):
		trace_riser_gap_px = v
		_queue_traces()

## Readout column's minimum width. Tentative.
@export_range(120, 600, 1, "suffix:px") var readout_min_width_px: int = 260:
	set(v):
		readout_min_width_px = v
		_apply_vessel()

## Stroke of a trace — fan_trace's line width. Tentative.
@export_range(0.5, 8.0, 0.5, "suffix:px") var trace_width_px: float = 2.5:
	set(v):
		trace_width_px = v
		_queue_traces()

## Glow tier a filled trace lights at, in its aspect's tint.
@export var trace_tier: Emissive.Tier = Emissive.Tier.VALUE:
	set(v):
		trace_tier = v
		_queue_traces()

@onready var _spell_bar: SpellPickerBar = %SpellPickerBar
@onready var _spell_scroll: ScrollContainer = %SpellScroll
@onready var _picker_panel: PanelContainer = %PickerPanel
@onready var _spell_button: SpellPickerButton = %SpellButton
@onready var _reset_button: Button = %ResetButton
@onready var _launch_button: LaunchAttackButton = %LaunchButton
@onready var _infusion_sockets: InfusionSockets = %InfusionSockets
@onready var _readout: CrucibleReadout = %CrucibleReadout
@onready var _readout_scroll: ScrollContainer = %ReadoutScroll
@onready var _crucible: VBoxContainer = %Crucible
@onready var _vessel_slot: Control = %VesselSlot
@onready var _circle: ArcaneCircle = %Circle
@onready var _traces: Control = %Traces
@onready var _trace_room: Control = %TraceRoom

## Sockets whose hover is already forwarded to the readout, by instance id —
## [InfusionSockets] rebuilds its sockets when the slot count moves.
var _hover_wired: Dictionary = {}


## Wired here rather than in [method _on_bound] because it is pure layout —
## it must hold in the editor and in a test that never calls [method bind].
func _ready() -> void:
	_spell_bar.layout_changed.connect(_on_bar_layout_changed)
	_on_bar_layout_changed(_spell_bar.get_row_count(), _spell_bar.get_button_px())
	_picker_panel.minimum_size_changed.connect(_place_picker)
	item_rect_changed.connect(_place_picker)
	# The collapsed button's press always opens the picker, castable or not:
	# the caster gate's denial toast belongs to the bar's tiles.
	_spell_button.set_has_caster(true)
	_traces.draw.connect(_draw_traces)
	_readout.anchors_changed.connect(_queue_traces)
	_readout_scroll.get_v_scroll_bar().value_changed.connect(_queue_traces.unbind(1))
	_infusion_sockets.item_rect_changed.connect(_queue_traces)
	_infusion_sockets.wheel().hovered.connect(_on_wedge_hovered)
	_apply_vessel()
	_place_picker()


## Push the vessel and column knobs into the scene.
func _apply_vessel() -> void:
	if not is_node_ready():
		return
	var edge := Vector2.ONE * vessel_px
	_vessel_slot.custom_minimum_size = edge
	_spell_button.custom_minimum_size = edge
	_circle.position = edge * 0.5
	_circle.radius = vessel_px * 0.45
	_crucible.add_theme_constant_override(&"separation", -arc_tuck_px)
	_readout_scroll.custom_minimum_size.x = readout_min_width_px
	_queue_traces()


## Under the arc, one turn step per owned socket so every trace's turn fits.
func _queue_traces() -> void:
	if _traces == null:
		return
	_trace_room.custom_minimum_size.y = trace_turn_step_px * _infusion_sockets.socket_count()
	_traces.queue_redraw()


## Each filled socket's trace, in %Traces' local coordinates, in socket order
## (socket 0, the rightmost, first — it feeds the topmost line). A socket whose
## line is missing from the readout gets none.
func trace_polylines() -> Array[PackedVector2Array]:
	var froms := PackedVector2Array()
	var tos := PackedVector2Array()
	var plan := _infusion_plan()
	if plan == null or not _infusion_sockets.visible:
		return []
	var to_local := _traces.get_global_transform().affine_inverse()
	var readout_xf := _readout.get_global_transform()
	for i in mini(plan.infusion.points.size(), _infusion_sockets.socket_count()):
		var anchor := _readout.line_anchor(i)
		var s := _infusion_sockets.socket(i)
		if anchor == Vector2.INF or s == null:
			break
		froms.append(to_local * (s.get_global_transform() * Vector2(s.size.x * 0.5, s.size.y)))
		tos.append(to_local * (readout_xf * anchor))
	return CrucibleTraces.route(froms, tos, trace_turn_step_px, trace_riser_gap_px)


func _infusion_plan() -> MagicAttackPlan:
	var plan := _armed_plan() as MagicAttackPlan if _armed_stack != null else null
	return plan if plan != null and plan.spell != null else null


## fan_trace's look: a constant-colour line in the aspect's tint at
## [member trace_tier], a solder pad at the socket end.
func _draw_traces() -> void:
	var plan := _infusion_plan()
	if plan == null:
		return
	var ids := plan.infusion.points.keys()
	var traces := trace_polylines()
	for k in traces.size():
		var aspect := AspectRoster.shared().by_id(ids[k])
		var base := aspect.identity.tint if aspect != null and aspect.identity != null else Color.WHITE
		var color := Emissive.at(base, Emissive.stops(trace_tier))
		_traces.draw_polyline(traces[k], color, trace_width_px, true)
		_traces.draw_circle(traces[k][0], trace_width_px * 1.4, color)


## Bottom edge [member picker_gap_px] above the body's top edge, growing up.
## `top_level`, so the position is canvas-global.
func _place_picker() -> void:
	if _picker_panel == null:
		return
	_picker_panel.size = Vector2(picker_width_px, 0.0)
	_picker_panel.global_position = global_position \
			- Vector2(0.0, _picker_panel.size.y + picker_gap_px)


## Size the scroll viewport to the rows we actually show, capped at
## [constant MAX_VISIBLE_ROWS]. Growing to a second row lifts the tray a little
## over the graph (it is bottom-anchored), which is fine; a third row must not,
## so past the cap the extra rows scroll.
func _on_bar_layout_changed(row_count: int, button_px: float) -> void:
	var shown := clampi(row_count, 1, MAX_VISIBLE_ROWS)
	var h := shown * button_px + (shown - 1) * SpellPickerBar.V_SEPARATION
	_spell_scroll.custom_minimum_size = Vector2(0.0, h)


func _on_bound() -> void:
	_spell_bar.bind_spellbook(_player.spellbook)
	_spell_bar.spell_selected.connect(_on_spell_selected)
	_reset_button.pressed.connect(_reset_plan)
	_launch_button.pressed.connect(_on_launch_pressed)
	_spell_button.pressed.connect(_on_spell_button_pressed)
	if _armed_stack != null:
		_armed_stack.changed.connect(_clear_stale_preview)
		_armed_stack.attack_plan_state_changed.connect(_refresh)
		_armed_stack.changed.connect(_repaint_picker)
		_armed_stack.selected_spell_changed.connect(_spell_bar.sync_selected)
	if _input_ctl != null:
		_input_ctl.player_can_act_changed.connect(_on_can_act_changed)
		_spell_bar.set_enabled(_input_ctl.can_player_act())
		_spell_button.set_actionable(_input_ctl.can_player_act())
	var picked := _armed_stack.memory_for(_player).magic.selected_spell if _armed_stack != null else null
	if picked != null:
		_spell_bar.sync_selected(picked)
	_repaint_picker()
	_refresh()


func teardown() -> void:
	_infusion_sockets.bind(null)
	_readout.bind(null)
	if _armed_stack != null and _armed_stack.changed.is_connected(_clear_stale_preview):
		_armed_stack.changed.disconnect(_clear_stale_preview)
	if _armed_stack != null and _armed_stack.selected_spell_changed.is_connected(_spell_bar.sync_selected):
		_armed_stack.selected_spell_changed.disconnect(_spell_bar.sync_selected)
	if _armed_stack != null and _armed_stack.attack_plan_state_changed.is_connected(_refresh):
		_armed_stack.attack_plan_state_changed.disconnect(_refresh)
	if _armed_stack != null and _armed_stack.changed.is_connected(_repaint_picker):
		_armed_stack.changed.disconnect(_repaint_picker)
	if _spell_button.pressed.is_connected(_on_spell_button_pressed):
		_spell_button.pressed.disconnect(_on_spell_button_pressed)
	if _input_ctl != null and _input_ctl.player_can_act_changed.is_connected(_on_can_act_changed):
		_input_ctl.player_can_act_changed.disconnect(_on_can_act_changed)


## A tile press is the open picker's pick — it writes the sticky spell and
## closes. No picker on the branch, nothing to pick for.
func _on_spell_selected(spell: SpellDef) -> void:
	var picker := _armed_stack.find(SpellPickMode) as SpellPickMode if _armed_stack != null else null
	if picker != null:
		picker.pick(spell)


func _on_spell_button_pressed() -> void:
	var magic := _armed_stack.find(MagicMode) as MagicMode if _armed_stack != null else null
	if magic != null:
		magic.toggle_picker()
	_repaint_picker()


## Shown iff the stack holds a [SpellPickMode]. On [signal ArmedStack.changed]
## only — never on `attack_plan_state_changed`, which every hover emits. The
## collapsed button reads pressed while the picker is open.
func _repaint_picker() -> void:
	var open := _armed_stack != null and _armed_stack.find(SpellPickMode) != null
	_picker_panel.visible = open
	_spell_button.set_selected(open)
	if open:
		_place_picker()


func _on_can_act_changed(can_act: bool) -> void:
	_spell_bar.set_enabled(can_act)
	_spell_button.set_actionable(can_act)
	_refresh()


func _refresh() -> void:
	var plan := _armed_plan() as MagicAttackPlan
	_infusion_sockets.bind(plan, _armed_stack)
	_readout.bind(plan)
	_wire_socket_hover()
	_queue_traces()
	if plan != null:
		_spell_bar.update_gating_context(plan.attacker)
	if plan != null and plan.spell != null and _spell_button.spell != plan.spell:
		_spell_button.spell = plan.spell
	var spell_name := plan.spell.name if plan != null and plan.spell != null else "Spell"
	_launch_button.text = "Cast %s" % spell_name
	var can_act := _input_ctl == null or (_input_ctl.can_player_act() and _input_ctl.can_afford(plan))
	_launch_button.set_enabled(plan != null and plan.is_valid() and can_act)


## Forward each socket's hover to the readout, once per socket node.
func _wire_socket_hover() -> void:
	for i in _infusion_sockets.socket_count():
		var s := _infusion_sockets.socket(i)
		if s == null or _hover_wired.has(s.get_instance_id()):
			continue
		_hover_wired[s.get_instance_id()] = true
		s.mouse_entered.connect(_readout.set_hovered_socket.bind(s.index))
		s.mouse_exited.connect(_on_socket_unhovered.bind(s.index))


func _on_socket_unhovered(index: int) -> void:
	if _readout.hovered_socket() == index:
		_readout.set_hovered_socket(-1)


## A wheel wedge previews "if you socket this here" on the open socket.
func _on_wedge_hovered(id: StringName) -> void:
	var open := _armed_stack.find(InfusionPickMode) as InfusionPickMode if _armed_stack != null else null
	if open == null or id == &"":
		_readout.clear_preview()
	else:
		_readout.preview_wedge(open.socket, id)


## The wheel closed (every close path is a stack change): drop its preview.
func _clear_stale_preview() -> void:
	if _armed_stack == null or _armed_stack.find(InfusionPickMode) == null:
		_readout.clear_preview()


func _on_launch_pressed() -> void:
	_battle_system.launch_attack(_armed_plan())
