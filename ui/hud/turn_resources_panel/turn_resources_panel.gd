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
##
## Root stays a plain Control; [method _get_minimum_size] forwards from
## "Margin" so a Container parent (HudRoot's LeftColumnSlot) sees this
## card's real size instead of the (0,0) a plain Control reports by
## default. See attributes_panel.gd for the identical pattern + writeup.

## Per-bucket "info line" shown in [member _sp_detail] on
## [signal CompositeBarGauge.segment_hovered] — sleek stand-in for a
## floating tooltip: the legend row already carries the labels/colors, so
## hover just brightens the matching entry and fills in one extra
## descriptive line rather than spawning a separate popup widget.
const _BUCKET_DESC := {
	CompositeBarGauge.Bucket.TO_SPEND: "Unspent — ready to allocate a node.",
	CompositeBarGauge.Bucket.ALLOCATED: "Locked into currently-owned nodes.",
	CompositeBarGauge.Bucket.WOUNDED: "Lost to a forced deallocation — heals over time.",
	CompositeBarGauge.Bucket.STAKED: "Committed to a node's raised allocation cap.",
}

@onready var _margin: MarginContainer = %Margin
@onready var _ap_gauge: PoolGauge = %APGauge
@onready var _dp_gauge: PoolGauge = %DPGauge
@onready var _mp_gauge: PoolGauge = %MPGauge
@onready var _sp_bar: CompositeBarGauge = %SPBar
@onready var _sp_to_spend_value: Label = %SPToSpendValue
@onready var _sp_wound_heal_label: Label = %WoundHealLabel
@onready var _sp_wound_heal_progress: ProgressBar = %Progress
@onready var _sp_detail: Label = %SPDetailLabel

@onready var _legend_labels: Dictionary[int, Label] = {
	CompositeBarGauge.Bucket.TO_SPEND: %ToSpendLabel,
	CompositeBarGauge.Bucket.ALLOCATED: %AllocatedLabel,
	CompositeBarGauge.Bucket.WOUNDED: %WoundedLabel,
	CompositeBarGauge.Bucket.STAKED: %StakedLabel,
}

var _board: StatBoard
var _legend_base_alpha: Dictionary[int, float] = {}
var _mp_base_glow: Color = Color(0, 0, 0, 0)
## Everything this panel connects to the CURRENT hero's pools, released as a
## unit when `bind` re-points at a different board (#459 hot-seat handover).
var _binds := BindScope.new()


func _get_minimum_size() -> Vector2:
	var margin := get_node_or_null(^"%Margin") as MarginContainer
	return margin.get_combined_minimum_size() if margin != null else Vector2.ZERO


func _ready() -> void:
	_margin.minimum_size_changed.connect(update_minimum_size)
	for bucket in _legend_labels:
		_legend_base_alpha[bucket] = _legend_labels[bucket].modulate.a
	_sp_wound_heal_progress.max_value = 1.0
	if _sp_bar != null:
		_sp_bar.segment_hovered.connect(_on_segment_hovered)
		_sp_bar.segment_unhovered.connect(_on_segment_unhovered)
	if _mp_gauge != null:
		_mp_base_glow = _mp_gauge.glow_color


func bind(board: StatBoard) -> void:
	_binds.release()
	_board = board
	if _board == null:
		return
	_bind_cells(_ap_gauge, _board.action_points)
	_bind_cells(_dp_gauge, _board.deallocation_points)
	_bind_cells(_mp_gauge, _board.movement_points)
	_bind_skill_points(_board.skill_points)


## Wired by [HudRoot] (#118) so the Move battery itself lights up while a core
## move is being targeted — colocated feedback on the existing bar rather
## than a second standalone widget (the old [ContextPanel]'s [CoreMoveBody]
## rendered its own separate MP bar; this reacts on the one that's already
## on-screen instead).
func bind_input_ctl(input_ctl: PlayerInputController) -> void:
	if input_ctl != null and not input_ctl.core_move_targeting_changed.is_connected(_on_core_move_targeting_changed):
		input_ctl.core_move_targeting_changed.connect(_on_core_move_targeting_changed)


func _on_core_move_targeting_changed(source: SkillNode) -> void:
	if _mp_gauge == null:
		return
	_mp_gauge.glow_color = Color(1.0, 1.0, 1.0, 0.9) if source != null else _mp_base_glow


func _bind_cells(gauge: PoolGauge, pool: PoolStat) -> void:
	if gauge == null or pool == null:
		return
	gauge.min_value = 0.0
	var surplus_gauge := gauge as SurplusPoolGauge
	var surplus_pool := pool as SurplusPoolStat
	var sync := func():
		gauge.max_value = float(pool.value)
		gauge.cell_count = float(pool.value)
		gauge.current = float(pool.current)
		# DP/MP carry a transient surplus bin (#152) shown as trailing cells.
		if surplus_gauge != null and surplus_pool != null:
			surplus_gauge.surplus = float(surplus_pool.surplus)
	_binds.link(pool.current_changed, sync.unbind(1))
	_binds.link(pool.value_changed, sync)
	if surplus_pool != null:
		_binds.link(surplus_pool.surplus_changed, sync)
	# The first paint is a BIND, not a spend: snapped, so a hot-seat handover to
	# a hero with fewer points doesn't ignite the difference as if it had just
	# been spent. Every later sync runs off a pool signal and is free to spark.
	gauge.begin_snap()
	sync.call()
	gauge.end_snap()


func _bind_skill_points(sp: SkillPointStat) -> void:
	if _sp_bar == null or sp == null:
		return
	var sync := func():
		_sp_bar.set_buckets(float(sp.current), float(sp.wounded), float(sp.staked), float(sp.value))
		_sp_bar.cell_count = float(sp.value)
		if _sp_to_spend_value != null:
			_sp_to_spend_value.text = str(int(sp.current))
			# #390 — "glows only when > 0" is VALUE-vs-INERT, not a static
			# alpha dimmer; alpha stays reserved for animated reveals.
			_sp_to_spend_value.modulate = Emissive.at(Color.WHITE, Emissive.VALUE) \
					if sp.current > 0 else Emissive.at(Color.WHITE, Emissive.INERT)
		_refresh_legend(sp)
		_refresh_wound_heal(sp)
	_binds.link(sp.current_changed, sync.unbind(1))
	_binds.link(sp.value_changed, sync)
	_binds.link(sp.wound_heal_progress_changed, func(_p): _refresh_wound_heal(sp))
	sync.call()


func _refresh_legend(sp: SkillPointStat) -> void:
	_set_legend_count(CompositeBarGauge.Bucket.TO_SPEND, int(sp.current))
	_set_legend_count(CompositeBarGauge.Bucket.ALLOCATED, int(sp.used))
	_set_legend_count(CompositeBarGauge.Bucket.WOUNDED, sp.wounded)
	_set_legend_count(CompositeBarGauge.Bucket.STAKED, sp.staked)


func _set_legend_count(bucket: int, count: int) -> void:
	var label: Label = _legend_labels.get(bucket)
	if label == null:
		return
	var noun: String = ["to-spend", "allocated", "wounded", "staked"][bucket]
	label.text = "%s %d" % [noun, count]


## Always visible — the heal rate is a stat the player wants to know even
## unwounded. The sliver tracks [member SkillPointStat.wound_heal_progress]
## (0..1 toward the next whole-SP heal); it holds full while there's
## nothing to heal (see that property's doc comment) instead of resetting.
func _refresh_wound_heal(sp: SkillPointStat) -> void:
	if _board == null:
		return
	var heal_rate: float = _board.wound_heal_per_turn.value if _board.wound_heal_per_turn != null else 0.0
	if _sp_wound_heal_label != null:
		var suffix := " · %d wounded" % sp.wounded if sp.wounded > 0 else ""
		_sp_wound_heal_label.text = "◷ wound heal %s/turn%s" % [_format_rate(heal_rate), suffix]
	if _sp_wound_heal_progress != null:
		_sp_wound_heal_progress.value = sp.wound_heal_progress


func _format_rate(rate: float) -> String:
	return str(int(rate)) if is_equal_approx(rate, roundf(rate)) else str(rate)


func _on_segment_hovered(bucket: int) -> void:
	for b in _legend_labels:
		var label := _legend_labels[b]
		label.modulate.a = 1.0 if b == bucket else _legend_base_alpha[b] * 0.4
	if _sp_detail != null:
		_sp_detail.text = _BUCKET_DESC.get(bucket, "")
		_sp_detail.modulate = Color(_legend_labels[bucket].modulate.r, _legend_labels[bucket].modulate.g, _legend_labels[bucket].modulate.b, 1.0)


func _on_segment_unhovered() -> void:
	for b in _legend_labels:
		_legend_labels[b].modulate.a = _legend_base_alpha[b]
	if _sp_detail != null:
		_sp_detail.modulate.a = 0.0
