@tool
class_name MagicBody
extends CommandTrayBodyBase
## Magic tab content (#114): reuses [SpellPickerBar]/[SpellPickerButton]
## verbatim (mana-cost/lock-state logic already lives there — see #114's
## explicit "don't rebuild the spell bar from scratch") + a Launch button
## whose label mirrors the currently-equipped spell.
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

@onready var _context_label: Label = %ContextLabel
@onready var _spell_bar: SpellPickerBar = %SpellPickerBar
@onready var _spell_scroll: ScrollContainer = %SpellScroll
@onready var _reset_button: Button = %ResetButton
@onready var _launch_button: LaunchAttackButton = %LaunchButton


## Wired here rather than in [method _on_bound] because it is pure layout —
## it must hold in the editor and in a test that never calls [method bind].
func _ready() -> void:
	_spell_bar.layout_changed.connect(_on_bar_layout_changed)
	_on_bar_layout_changed(_spell_bar.get_row_count(), _spell_bar.get_button_px())


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
	_battle_system.selected_spell_changed.connect(_spell_bar.sync_selected)
	_reset_button.pressed.connect(_battle_system.reset_plan)
	_launch_button.pressed.connect(_battle_system.launch_attack)
	_battle_system.attack_plan_state_changed.connect(_refresh)
	if _input_ctl != null:
		_input_ctl.player_can_act_changed.connect(_on_can_act_changed)
		_spell_bar.set_enabled(_input_ctl.can_player_act())
	if _battle_system.selected_spell != null:
		_spell_bar.sync_selected(_battle_system.selected_spell)
	_refresh()


func teardown() -> void:
	if _battle_system.selected_spell_changed.is_connected(_spell_bar.sync_selected):
		_battle_system.selected_spell_changed.disconnect(_spell_bar.sync_selected)
	if _battle_system.attack_plan_state_changed.is_connected(_refresh):
		_battle_system.attack_plan_state_changed.disconnect(_refresh)
	if _input_ctl != null and _input_ctl.player_can_act_changed.is_connected(_on_can_act_changed):
		_input_ctl.player_can_act_changed.disconnect(_on_can_act_changed)


func _on_spell_selected(spell: SpellDef) -> void:
	_battle_system.selected_spell = spell


func _on_can_act_changed(can_act: bool) -> void:
	_spell_bar.set_enabled(can_act)
	_refresh()


func _refresh() -> void:
	var plan := _battle_system.attack_plan as MagicAttackPlan
	var board := _player.stat_board if _player != null else null
	var mana: float = float(board.mana.current) if board != null and board.mana != null else 0.0
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
	_context_label.text = "source degree %d · mana %d" % [degree, int(mana)]
	if plan != null:
		_spell_bar.update_gating_context(plan.attacker)
	var spell_name := plan.spell.name if plan != null and plan.spell != null else "Spell"
	_launch_button.text = "Cast %s" % spell_name
	var can_act := _input_ctl == null or _input_ctl.can_player_act()
	_launch_button.set_enabled(plan != null and plan.is_valid() and can_act)
