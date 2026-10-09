@tool
class_name MagicBody
extends CommandTrayBodyBase
## Magic tab content (#114): reuses [SpellPickerBar]/[SpellPickerButton]
## verbatim (gating/lock-state logic already lives there — see #114's
## explicit "don't rebuild the spell bar from scratch") + a Launch button
## whose label mirrors the currently-equipped spell.
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

## Minimum width of each of the four %Sections columns (Cast / On arrival /
## Then / Crits); the lines wrap inside it.
@export_range(80, 400, 1, "suffix:px") var section_min_width: int = 180:
	set(v):
		section_min_width = v
		_size_sections()

@onready var _context_label: Label = %ContextLabel
@onready var _spell_bar: SpellPickerBar = %SpellPickerBar
@onready var _spell_scroll: ScrollContainer = %SpellScroll
@onready var _picker_panel: PanelContainer = %PickerPanel
@onready var _spell_button: SpellPickerButton = %SpellButton
@onready var _reset_button: Button = %ResetButton
@onready var _launch_button: LaunchAttackButton = %LaunchButton
@onready var _infusion_row: InfusionRow = %InfusionRow
@onready var _affinity_line: AffinityLine = %AffinityLine
@onready var _sections: Array[SpellTooltipSection] = [%CastSection, %OnArrivalSection,
		%ThenSection, %CritsSection]

## The (plan, spell, source) the %Sections were last built for — see [method _show_sections].
var _sections_plan: MagicAttackPlan = null
var _sections_spell: SpellDef = null
var _sections_source: SkillNode = null


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
	# The configure view shares the body's height budget with the sections and
	# the infusion row, so the collapsed tile is the bar's compact edge.
	_spell_button.custom_minimum_size = Vector2.ONE * SpellPickerBar.COMPACT_BUTTON_PX
	_place_picker()
	_size_sections()


func _size_sections() -> void:
	for section in _sections:
		section.custom_minimum_size.x = section_min_width


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
	_infusion_row.bind(null)
	_affinity_line.bind(null)
	_show_sections(null)
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
	_infusion_row.bind(plan)
	_affinity_line.bind(plan)
	_show_sections(plan)
	# Post-#728 there is no cast-from node until a target is clicked, so this
	# reads 0 until one is auto-picked. Deliberately NOT "the best degree the
	# territory offers": _refresh runs on attack_plan_state_changed, which
	# every hover emits, and a max-degree scan is a degree query per owned node
	# per mouse move — the exact per-point-predicate shape .claude/rules/graph.md
	# warns about. The picker's caster gate already says whether a spell is
	# castable at all, and it costs nothing here.
	var degree := 0
	if plan != null and plan.source != null and _player.navigator != null:
		degree = _player.navigator.get_degree(plan.source)
	_context_label.text = "source degree %d" % degree
	if plan != null:
		_spell_bar.update_gating_context(plan.attacker)
	if plan != null and plan.spell != null and _spell_button.spell != plan.spell:
		_spell_button.spell = plan.spell
	var spell_name := plan.spell.name if plan != null and plan.spell != null else "Spell"
	_launch_button.text = "Cast %s" % spell_name
	var can_act := _input_ctl == null or (_input_ctl.can_player_act() and _input_ctl.can_afford(plan))
	_launch_button.set_enabled(plan != null and plan.is_valid() and can_act)


## The four marked sections of [param plan]'s spell, from [method SpellSections.build]
## with the caster's board and the plan's cast-from node (the landing's read
## node, so a node-local bonus shows as it lands) — the tooltip's own
## derivation; nothing about a spell is derived here. [method _refresh] runs on
## every hover, so the build happens only when (plan, spell, source) moved since
## the last one. A caster stat moving mid-arm shows on the next such change.
func _show_sections(plan: MagicAttackPlan) -> void:
	var spell := plan.spell if plan != null else null
	var source := plan.source if plan != null else null
	if plan == _sections_plan and spell == _sections_spell and source == _sections_source:
		return
	_sections_plan = plan
	_sections_spell = spell
	_sections_source = source
	var board := plan.attacker.stat_board if plan != null and plan.attacker != null else null
	var built := SpellSections.build(spell, board, source)
	var lines: Array[SpellSections.Lines] = [built.cast, built.on_arrival, built.then, built.crits]
	for i in _sections.size():
		_sections[i].bind(lines[i].lines, lines[i].dynamic)


func _on_launch_pressed() -> void:
	_battle_system.launch_attack(_armed_plan())
