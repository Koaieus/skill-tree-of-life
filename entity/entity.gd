@tool
class_name Entity
extends Node

## An entity that lives on the skill tree. Owns a connected induced
## subgraph of SkillNodes. Identity + colour + an optional stat board, plus
## a child `EntityNavigator` that mirrors the owned-subgraph for connectivity
## queries (islanding checks now; combat path/reach queries later).

signal core_location_changed
signal leveled_up(new_level: int)

@export var display_name: String = "Entity"
@export var color: Color = Color.WHITE
@export var stat_board: StatBoard = null
@export var core_location: SkillNode:
	set(value):
		if core_location == value:
			return
		core_location = value
		core_location_changed.emit()

## Current level. Bumps on every xp pool fill via `_on_xp_replenished`.
## Tracked here (not on the stat board) so the signal payload is meaningful
## without a dedicated `level` Stat — promote to a real stat if level-scaling
## modifiers start showing up.
var level: int = 1

## Auto-created on _ready when the entity has a Graph ancestor. Stays null
## in editor (`@tool` short-circuit) and in stand-alone tests with no graph.
var navigator: EntityNavigator


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var g := _find_graph()
	if g == null:
		push_warning("Entity '%s' has no Graph ancestor; navigator disabled" % display_name)
	else:
		navigator = EntityNavigator.new()
		navigator.name = "EntityNavigator"
		navigator.entity = self
		navigator.graph = g
		add_child(navigator)

	if stat_board != null and stat_board.xp != null:
		stat_board.xp.replenished.connect(_on_xp_replenished)

	var tm := _find_turn_manager()
	if tm != null:
		tm.turn_started.connect(_on_turn_started)


## Listens for TurnManager.turn_started. Each entity self-handles its own
## start-of-turn upkeep so we don't grow a god-mode TurnManager. Per-turn
## bookkeeping today: reset AP/DP to full, tick XP by xp_per_turn.
func _on_turn_started(entity: Entity) -> void:
	if entity != self or stat_board == null:
		return
	if stat_board.action_points != null:
		stat_board.action_points.restore_to_full()
	if stat_board.deallocation_points != null:
		stat_board.deallocation_points.restore_to_full()
	if stat_board.xp != null and stat_board.xp_per_turn != null:
		var gain := int(stat_board.xp_per_turn.value)
		if gain > 0:
			stat_board.xp.replenish(gain)


## Listens for xp.replenished (pool crossed into full). Grows the xp cap via
## its formula, deducts the old cap from current (carrying overflow if the
## pool ever permits it), bumps SP max — SP's heal_on_max_increase=true takes
## care of the matching +1 current — then emits leveled_up.
func _on_xp_replenished() -> void:
	if stat_board == null or stat_board.xp == null:
		return
	var xp_pool := stat_board.xp
	var old_max := int(xp_pool.max_value)
	xp_pool.grow()
	xp_pool.set_current(max(0.0, xp_pool.current - float(old_max)))

	if stat_board.skill_points_max != null:
		stat_board.skill_points_max.base_value += 1.0

	level += 1
	leveled_up.emit(level)


func _find_turn_manager() -> TurnManager:
	var n: Node = self
	while n != null:
		for c in n.get_children():
			if c is TurnManager:
				return c as TurnManager
		n = n.get_parent()
	return null


func _find_graph() -> Graph:
	var n: Node = get_parent()
	while n != null:
		if n is Graph:
			return n as Graph
		n = n.get_parent()
	return null


func _to_string() -> String:
	return "Entity<%s--%s>" % [display_name, core_location as Variant if core_location else 'N/A']
