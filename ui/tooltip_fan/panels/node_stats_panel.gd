@tool
class_name NodeStatsPanel
extends FanPanel

## Tooltip V2 (#226/#230) — crown, NEAR rung (node-scoped), left by default.
## Envelope sized to the worst case per the "Crown envelope inputs" comment:
## 2 always-shown rows + local/aura stats, 8 rows of headroom.
##
## [method bind] renders, in order: Node HP + Armor (always, when allocated —
## see [method _add_always_shown_rows]), then one [StatValueRow] per stat
## found on [member SkillNode.node_board] via
## [method StatBoard.get_dynamic_stat_ids] (already on master — consumed
## here, NOT re-added to `stats_system/stat_board.gd`, which this panel does
## not own).
##
## Offensive damage stats are deliberately excluded from that enumeration —
## [CombatReadoutCard._local_override_or_null] already previews
## `blade_damage`/`ranged_damage`/`range` on hover, and a second display of
## the same number that must agree with the first is exactly what this
## design avoids. See [constant _EXCLUDED_STAT_IDS].
##
## [method has_content] answers false for an unowned node with no node-local
## stats — it has no combat identity worth a panel.

const _ENVELOPE_ROWS := 8

## Offensive damage stats stay out of this panel (settled, #230) — they're
## already previewed by CombatReadoutCard on hover, and duplicating them here
## risks the two displays disagreeing.
const _EXCLUDED_STAT_IDS: Array[StringName] = [&"blade_damage", &"ranged_damage", &"range"]

## Rendered via the dedicated always-shown rows ([method _add_always_shown_rows]),
## not the generic enumeration — skip them there so they don't double-render.
const _ALWAYS_SHOWN_STAT_IDS: Array[StringName] = [&"node_health", &"armor", &"min_damage_taken"]

const _STAT_VALUE_ROW_SCENE: PackedScene = preload("res://ui/tooltip_fan/stat_value_row.tscn")

## Per-index reveal delay (fraction of the panel's own `progress`) — same
## staggered-reveal shape as [AddonsPanel] / [GrantedModifiersRoot].
const _ROW_STAGGER_STEP := 0.12
const _ROW_STAGGER_CAP := 0.85

## The node currently rendered, if any (set by [method bind]).
var _bound_node: SkillNode = null

## One entry per rendered row, parallel to `_rows`' children — drives the
## staggered reveal from [method _apply_progress].
var _row_setters: Array[Callable] = []


func _ready() -> void:
	super._ready()
	# See owner_panel.gd's _ready for why this skips in-editor entirely.
	if Engine.is_editor_hint():
		return
	_header.bind("Node Stats")


## Public entry point (#230). `_graph` is unused here — this panel only ever
## reads node-local data.
func bind(node: SkillNode, _graph: Graph) -> void:
	_bound_node = node
	_rebuild_rows()
	_apply_row_stagger()


## False for an unowned node carrying no node-local stats — no combat
## identity worth a panel. [TooltipFan] suppresses the unit entirely rather
## than showing an empty box.
func has_content() -> bool:
	if _bound_node == null:
		return false
	if _bound_node.is_allocated():
		return true
	return not _visible_dynamic_ids().is_empty()


func _rebuild_rows() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_row_setters.clear()
	if _bound_node == null:
		return
	if _bound_node.is_allocated():
		_add_always_shown_rows()
	for id in _visible_dynamic_ids():
		_add_scalar_row(id)


## Node HP (numeric, never a bar — the floating bar keeps its own lifetime
## outside the fan) + the combined "Armor: N (M)" row, both shown unconditionally
## once the node is allocated, even with no local modifier present.
func _add_always_shown_rows() -> void:
	var hp_def: StatDef = StatRegistry.get_def(&"node_health")
	if hp_def != null:
		var row := _STAT_VALUE_ROW_SCENE.instantiate() as StatValueRow
		_rows.add_child(row)
		row.bind_pool(hp_def, _bound_node.get_current_hp(), _bound_node.get_max_hp())
		_row_setters.append(row.set_progress)
	var armor_def: StatDef = StatRegistry.get_def(&"armor")
	if armor_def != null:
		var armor: float = float(_bound_node.get_local_value(&"armor"))
		var min_damage: float = float(_bound_node.get_local_value(&"min_damage_taken"))
		var row := _STAT_VALUE_ROW_SCENE.instantiate() as StatValueRow
		_rows.add_child(row)
		row.bind_parenthetical(armor_def, armor, min_damage)
		_row_setters.append(row.set_progress)


func _add_scalar_row(id: StringName) -> void:
	var def: StatDef = StatRegistry.get_def(id)
	if def == null:
		return
	var row := _STAT_VALUE_ROW_SCENE.instantiate() as StatValueRow
	_rows.add_child(row)
	row.bind_scalar(def, float(_bound_node.get_local_value(id)))
	_row_setters.append(row.set_progress)


## Every stat id live on [member SkillNode.node_board] — baked node-only ones
## (`stake_level`, `addon_slots`) and dynamically minted borrowed ones — minus the
## offensive stats this panel deliberately excludes and the ids already
## rendered by [method _add_always_shown_rows]. Empty (never null) when the
## node has no node_board or no dynamic stats.
func _visible_dynamic_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	if _bound_node == null or _bound_node.node_board == null:
		return result
	for id in _bound_node.node_board.get_stat_ids():
		if id in _EXCLUDED_STAT_IDS or id in _ALWAYS_SHOWN_STAT_IDS:
			continue
		# `addon_slots` is baked on every node board now (#332) rather than minted
		# when the first addon lands, so without this an addonless node would gain
		# a permanent "Addon Slots 0" row it never used to have. The cap is
		# advisory until player-managed placement exists (#348) — worth showing
		# where addons actually are, noise everywhere else.
		if id == &"addon_slots" and _bound_node.get_addons().is_empty():
			continue
		result.append(id)
	return result


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
