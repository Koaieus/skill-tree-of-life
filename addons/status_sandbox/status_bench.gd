@tool
extends Node2D

## One node, one Bearer, one TurnManager: the Status tab's world, scene-authored
## (see `status_bench.tscn` and its inherited setups). The panel instantiates a
## setup and calls [method arm]; Reset is [method disarm] + `free()` + a fresh
## instance, never an in-place undo.
##
## The bench owns its TurnManager rather than letting the scaffold build one,
## because the sandbox host instantiates every live tab into one tree: it is
## scoped to this bench's Graph (`entity_root`) and the Bearer is wired to it
## (`turn_manager_override`), so ▶ Tick turn serves this Bearer and nobody else.
## It is built in code, not authored in the `.tscn`: `turn_manager.gd` is not
## `@tool`, so an authored one is a placeholder instance in the editor.
##
## Statuses land through the real hit path ([method apply_status]), so potency
## and resistance scaling and the drained-core fall-through all apply.

const _SANDBOX_WORLD: Script = preload("res://scenes/dev/sandbox_world.gd")
const _FAN_GROUP := &"fan_unit"
## The fan units this bench pins open (when they have content); the rest stay hidden.
const _PINNED_UNITS: Array[StringName] = [&"NodeStats", &"EffectReadout", &"Core"]

## Node HP after arm, as a fraction of its max. The drained setup authors 0.0:
## a cracked core, entity HP untouched.
@export_range(0.0, 1.0, 0.05) var node_hp_fraction := 1.0

@onready var graph: Graph = %Graph
@onready var node: SkillNode = %Node
@onready var bearer: Entity = %Bearer
## Built in [method _enter_tree]; handed to the scaffold via `adopt_turn_manager`.
var turn_manager: TurnManager = null
@onready var _fan: FanAnchorDriver = %Fan
@onready var _ring: Node2D = %VisionRing

var allocation_system: AllocationSystem
## Resistance stat id → the StatModifier the panel's slider writes (`value`,
## never the stat's `base_value`). Created on first use, on this bench's board.
var _resistance_mods: Dictionary[StringName, StatModifier] = {}


## Before any child's `_ready`: headless, the Bearer binds its TurnManager in
## its own `_ready`, so the override has to be in place by then.
func _enter_tree() -> void:
	if turn_manager != null:
		return
	turn_manager = TurnManager.new()
	turn_manager.name = "TurnManager"
	turn_manager.entity_root = get_node(^"Graph")
	add_child(turn_manager)
	(get_node(^"Graph/Entities/Bearer") as Entity).turn_manager_override = turn_manager


## Bring the authored world to life, in order: the Bearer first (under the
## editor hint nothing else would duplicate its board or bind its TurnManager),
## then the systems, then the ownership the scene authored, then the authored
## node HP, then the first turn.
func arm() -> void:
	bearer.initialize()
	var world = _SANDBOX_WORLD.new()
	world.name = "SandboxWorld"
	add_child(world)
	world.build(graph, {"adopt_turn_manager": turn_manager})
	allocation_system = world.allocation_system
	allocation_system.register_scene_authored_ownership()
	if node_hp_fraction < 1.0:
		node.restore_current_hp(node.get_max_hp() * node_hp_fraction)
	turn_manager.start_turn(bearer)

	node.damaged.connect(_on_world_changed.unbind(2))
	node.healed.connect(_on_world_changed.unbind(2))
	node.statuses_changed.connect(_on_world_changed)
	node.owner_changed.connect(_on_world_changed)
	bearer.statuses_changed.connect(_on_world_changed)

	_fan.node_radius = node.radius
	for m in _members():
		if m.has_method(&"enter_hidden"):
			m.enter_hidden()
	_ring.bind(node)
	_on_world_changed()


## Release the turn before the bench is freed, so the TurnManager's cursor never
## outlives the entity it points at.
func disarm() -> void:
	if turn_manager != null and bearer != null:
		turn_manager.abandon_turn(bearer)


## Land [param def] at [param power] on the node through [method StatusInstance.land_on]
## — no attacker, so potency is ×1; resistance is read on the receiving host,
## and a cracked core hands the row to the Bearer. Returns the landed instance
## (its `host_kind` and `power` say where and how much), or null when the node
## is unowned and nothing can land.
func apply_status(def: StatusDef, power: float) -> StatusInstance:
	if node.owned_by == null:
		return null
	var si := StatusInstance.new()
	si.def = def
	si.power = power
	si.attacker = null
	si.target = node
	si.land_on(node.get_combat(), CombatWorld.live())
	return si


func clear_statuses() -> void:
	node.get_combat().clear_statuses()
	bearer.get_combat().clear_statuses()


func cure(amount: float) -> void:
	node.get_combat().cure_debuffs(amount)


## Set the Bearer's [param stat_id] (a resistance) to [param value] by writing
## the bench's own modifier's `value` (`docs/domain/stat-knobs-and-bins.md`).
func set_resistance(stat_id: StringName, value: float) -> void:
	var m: StatModifier = _resistance_mods.get(stat_id)
	if m == null:
		m = StatModifier.new()
		m.stat_id = stat_id
		m.operation = StatModifier.Operation.ADD_BASE
		m.value = value
		_resistance_mods[stat_id] = m
		bearer.stat_board.add_modifier(m)
	else:
		m.value = value
	_ring.refresh()


func set_ring_visible(on: bool) -> void:
	_ring.visible = on


func get_vision_radius() -> float:
	return _ring.get_radius()


# --- the pinned fan (TooltipFan's bind/participate contract) -----------------

func _members() -> Array[Node]:
	var out: Array[Node] = []
	for n in _fan.find_children("*", "", true, false):
		if n.is_in_group(_FAN_GROUP) and n.has_method(&"play_in") and n.has_method(&"play_out"):
			out.append(n)
	return out


## Rebind every pinned unit and play in / out only those whose participation
## flipped — the panels already up stay up. No stagger: a delayed play-in would
## outlive a Reset that frees this bench.
func _on_world_changed() -> void:
	for m in _members():
		if not (m is FanUnit):
			continue
		var unit := m as FanUnit
		unit.bind(node, graph)
		unit.participating = unit.name in _PINNED_UNITS and unit.has_content()
		var is_up: bool = unit.state == FanUnit.State.IN or unit.state == FanUnit.State.LOOP
		if unit.participating and not is_up:
			unit.play_in()
		elif not unit.participating and is_up:
			unit.play_out()
	_ring.refresh()
