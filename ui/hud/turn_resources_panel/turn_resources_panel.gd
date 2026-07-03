@tool
class_name TurnResourcesPanel
extends Control
## Left column, third card (#110): Action/Dealloc/Move as segmented
## [PoolGauge] "battery" cells + the Skill Points [CompositeBarGauge] with
## legend + wound-heal sliver. The big "to-spend" number glows only when > 0
## (mostly 0 — all invested, per design).
##
## NOTE: the design's flex-wrap (late-game high-max pools tiling into rows)
## isn't implemented — each pool is one PoolGauge with cell_count == max,
## which reads fine up to the current stock caps (AP/DP/Move all <= ~5).
## Revisit with an HFlowContainer of PoolGauge strips if a run ever pushes
## a cap high enough to make single-row cells illegible.

@onready var _ap_gauge: PoolGauge = %APGauge
@onready var _dp_gauge: PoolGauge = %DPGauge
@onready var _mp_gauge: PoolGauge = %MPGauge
@onready var _sp_bar: CompositeBarGauge = %SPBar
@onready var _sp_to_spend_value: Label = %SPToSpendValue
@onready var _sp_wound_heal: Label = %SPWoundHeal

var _board: StatBoard


func bind(board: StatBoard) -> void:
	_board = board
	if _board == null:
		return
	_bind_cells(_ap_gauge, _board.action_points)
	_bind_cells(_dp_gauge, _board.deallocation_points)
	_bind_cells(_mp_gauge, _board.movement_points)
	_bind_skill_points(_board.skill_points)


func _bind_cells(gauge: PoolGauge, pool: PoolStat) -> void:
	if gauge == null or pool == null:
		return
	gauge.min_value = 0.0
	var sync := func():
		gauge.max_value = float(pool.value)
		gauge.cell_count = float(pool.value)
		gauge.current = float(pool.current)
	pool.current_changed.connect(sync.unbind(1))
	pool.value_changed.connect(sync)
	sync.call()


func _bind_skill_points(sp: SkillPointStat) -> void:
	if _sp_bar == null or sp == null:
		return
	var sync := func():
		_sp_bar.set_buckets(float(sp.current), float(sp.wounded), float(sp.staked), float(sp.value))
		if _sp_to_spend_value != null:
			_sp_to_spend_value.text = str(int(sp.current))
			_sp_to_spend_value.modulate = Color(1, 1, 1, 1) if sp.current > 0 else Color(1, 1, 1, 0.35)
		if _sp_wound_heal != null:
			var heal_rate: float = _board.wound_heal_per_turn.value if _board.wound_heal_per_turn != null else 0.0
			_sp_wound_heal.visible = sp.wounded > 0
			_sp_wound_heal.text = "%d wounded, healing %d/turn" % [int(sp.wounded), int(heal_rate)]
	sp.current_changed.connect(sync.unbind(1))
	sp.value_changed.connect(sync)
	sync.call()
