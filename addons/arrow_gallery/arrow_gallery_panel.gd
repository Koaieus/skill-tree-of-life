@tool
extends PanelContainer

## Arrow gallery: fire a volley of any [AmmoType] in the roster at a dummy, and
## watch it render exactly as the game draws it.
##
## [b]A real launch on a sandbox board, never a hand-built outcome.[/b] Every
## Fire builds a fresh board from the real systems (the shared
## `sandbox_world.gd` scaffold) and goes through [method BattleSystem.launch_attack],
## so [ArrowVolleyCoordinator] draws what the game draws. Authoring an
## [AttackOutcome] by hand would be a second outcome producer; that is #534
## fork 4, and with it a per-arrow verdict mix inside one volley. Here a whole
## volley shares one verdict, chosen by a board PRESET:
##
## - [b]Dud[/b]: the defender's nodes are frail ([member frail_hp]), so the first
##   arrows deplete the dummy and later waves fail
##   [method RangedDamageFormula.passes_gate] on a node no longer allocated.
## - [b]Held[/b]: dummy `armor` ([member held_armor]) ≥ the raw shot and
##   `min_damage_taken` 0, so [Mitigation] yields exactly 0.
## - [b]Gained[/b]: armour plus a negative net `min_damage_taken`
##   ([member gained_min_damage_taken]), so the hit reclassifies to a HEAL.
## - [b]Crit[/b]: the attacker's `crit_chance` SET to 1.0 by a modifier.
##
## The type picker is filled from `ammo_type_roster.tres` at runtime, so a new
## arrow appears with no edit here. This tab owns the arrow LOOKS; the VFX tab's
## primitive gallery stays a catalogue of the parts a spell coordinator shops for.
##
## Board: the attacker's core with [constant LEAF_COUNT] reaching leaves (each
## fires up to [constant SHOTS_PER_LEAF] a turn, so 20 arrows fit), and a
## hostile cluster — the dummy, two neighbours, the defender's core — for the
## splash/flare looks. Target picks the dummy or a cluster neighbour; the
## Held / Gained presets arm whichever is picked.

signal reload_requested

enum Preset { NORMAL, DUD, HELD, GAINED, CRIT }

const _SANDBOX_WORLD: Script = preload("res://scenes/dev/sandbox_world.gd")
const _SKILL_NODE_SCENE: PackedScene = preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE: PackedScene = preload("res://graph/graph.tscn")
const _BOARD: Resource = preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION: Resource = preload("res://entity/factions/player.tres")
const _NPC_FACTION: Resource = preload("res://entity/factions/npc.tres")
const ROSTER_PATH := "res://attack/ammo/ammo_type_roster.tres"

const LEAF_COUNT := 5
const SHOTS_PER_LEAF := 4
const MAX_VOLLEY := LEAF_COUNT * SHOTS_PER_LEAF
const _LEAF_RADIUS := 170.0
const _LEAF_RANGE := 4000.0
## Node name -> position for the defender's half; the attacker's is a fan.
const _DEFENDER_LAYOUT: Array[Array] = [
	["d_target", Vector2(560, 0)],
	["d_left", Vector2(650, -120)],
	["d_right", Vector2(650, 120)],
	["d_core", Vector2(780, 0)],
]
const _DEFENDER_EDGES: Array[Array] = [
	["d_target", "d_left"], ["d_target", "d_right"],
	["d_left", "d_core"], ["d_right", "d_core"],
]
const _TARGETS: Array[String] = ["d_target", "d_left"]
const _FIT_MARGIN := 70.0

## Dud preset: the defender's `node_health`, low enough that the first arrows
## deplete the dummy. Tentative.
@export_range(1.0, 50.0, 1.0) var frail_hp: float = 1.0:
	set(v):
		frail_hp = v
		_rebuild_from_knob()
## Held preset: the dummy's `armor`; well above any crit, so every arrow holds.
@export_range(0.0, 9999.0, 1.0) var held_armor: float = 999.0:
	set(v):
		held_armor = v
		_rebuild_from_knob()
## Gained preset: the dummy's `armor`.
@export_range(0.0, 9999.0, 1.0) var gained_armor: float = 999.0:
	set(v):
		gained_armor = v
		_rebuild_from_knob()
## Gained preset: the dummy's net `min_damage_taken` — negative is a heal per
## arrow (`bunker_addon.tscn` authors −5).
@export_range(-50.0, 0.0, 1.0) var gained_min_damage_taken: float = -5.0:
	set(v):
		gained_min_damage_taken = v
		_rebuild_from_knob()
## [member BattleSystem.instant_mutation] for every fire — the headless smoke
## sets it; the tab leaves it off so the reveal clock plays.
@export var instant: bool = false

@onready var _world: SubViewport = %World
@onready var _world_host: Node2D = %WorldHost
@onready var _world_container: SubViewportContainer = %WorldContainer
## The real hover tooltip (EFFECTS + NODE STATS) over the world, re-mounted on
## every board rebuild (test hook).
@onready var tooltip_mount: SandboxTooltipFanMount = %TooltipFanMount
@onready var _type_list: OptionButton = %TypeList
@onready var _count: SpinBox = %Count
@onready var _preset_list: OptionButton = %PresetList
@onready var _target_list: OptionButton = %TargetList
@onready var _fire_button: Button = %FireBtn
@onready var _status: RichTextLabel = %StatusLabel

var _roster: AmmoTypeRoster
var _types: Array[AmmoType] = []
var _graph: Graph
var _sandbox: Node
var _battle: BattleSystem
var _attacker: Entity
var _defender: Entity
var _nodes: Dictionary[String, SkillNode] = {}
var _busy: bool = false
var _last_outcome: AttackOutcome
var _verdict: String = ""


func _ready() -> void:
	_roster = load(ROSTER_PATH) as AmmoTypeRoster
	_types = _roster.sorted() if _roster != null else ([] as Array[AmmoType])
	_type_list.clear()
	for t in _types:
		_type_list.add_item(t.display_name if t.display_name != "" else str(t.id))
	_preset_list.clear()
	for key in Preset.keys():
		_preset_list.add_item(str(key).capitalize())
	_target_list.clear()
	for t in _TARGETS:
		_target_list.add_item(t)
	_count.min_value = 1
	_count.max_value = MAX_VOLLEY
	_fire_button.pressed.connect(_on_fire_pressed)
	_world.size_changed.connect(_layout_world)
	tooltip_mount.attach_motion(_world_container, _pick_node_at)
	_build_board(Preset.NORMAL)
	_refresh_status()


## Sandbox-host contract: an [AmmoType] picked in the Inspector selects it.
func load_object(obj: Object) -> void:
	if obj is AmmoType:
		var i := _types.find(obj)
		if i >= 0:
			_type_list.selected = i


func type_count() -> int:
	return _types.size()


func type_at(i: int) -> AmmoType:
	return _types[i] if i >= 0 and i < _types.size() else null


## Rebuild the board under [param preset] and fire [param n] arrows of roster
## type [param type_index] at the target. Returns the committed outcome, or
## null if nothing launched. Awaits the whole swing.
func fire(type_index: int, preset: Preset, n: int, target_name: String = "d_target") -> AttackOutcome:
	var ammo := type_at(type_index)
	if ammo == null or _busy:
		return null
	_busy = true
	_refresh_status()
	_last_outcome = null
	_build_board(preset, target_name)
	var quiver := _attacker.stat_board.arrows
	var stocked := quiver.add(ammo.id, clampi(n, 1, MAX_VOLLEY), ammo.max_stock)
	var plan := _battle.new_plan(BattleSystem.AttackMode.RANGED, _attacker) as RangedAttackPlan
	if plan == null or not plan.set_target(_nodes[target_name]):
		_verdict = "[color=#ff8f6b]no ranged plan onto %s[/color]" % target_name
		_busy = false
		_refresh_status()
		return null
	plan.ammo = [{"type": ammo.id, "count": stocked}] as Array[Dictionary]
	await _battle.launch_attack(plan)
	_verdict = _describe(_last_outcome, ammo, preset)
	_busy = false
	_refresh_status()
	return _last_outcome


func _on_fire_pressed() -> void:
	fire(_type_list.selected, _preset_list.selected as Preset, int(_count.value),
			_TARGETS[maxi(0, _target_list.selected)])


# ── Board ────────────────────────────────────────────────────────────────────

## A fresh board per fire: statuses, stocks, shot budgets and a dead defender
## from the last volley never leak into the next. The old one is detached
## before the new one is named, so the two never collide.
func _build_board(preset: Preset, target_name: String = _TARGETS[0]) -> void:
	for old in [_sandbox, _graph]:
		if old != null and is_instance_valid(old):
			old.get_parent().remove_child(old)
			old.queue_free()
	_nodes.clear()
	_graph = _GRAPH_SCENE.instantiate() as Graph
	_graph.name = "Graph"
	_world_host.add_child(_graph)
	_add_node("a_core", Vector2.ZERO)
	for i in LEAF_COUNT:
		var angle := deg_to_rad(lerpf(-60.0, 60.0, float(i) / float(LEAF_COUNT - 1)))
		var leaf := _add_node("a_leaf%d" % i, Vector2.from_angle(angle) * _LEAF_RADIUS)
		_graph.add_edge(_nodes["a_core"], leaf)
		_set_local(leaf, &"range", _LEAF_RANGE)
		_set_local(leaf, &"max_shots_per_leaf", SHOTS_PER_LEAF)
	for entry in _DEFENDER_LAYOUT:
		_add_node(str(entry[0]), entry[1] as Vector2)
	for pair in _DEFENDER_EDGES:
		_graph.add_edge(_nodes[str(pair[0])], _nodes[str(pair[1])])
	_attacker = _spawn("Attacker", _PLAYER_FACTION)
	_defender = _spawn("Defender", _NPC_FACTION)
	# Board-scope presets go on BEFORE allocation, so every pool fills to the
	# preset's max rather than clamping down from the default.
	if preset == Preset.DUD:
		_defender.stat_board.add_modifier(_set_mod(&"node_health", frail_hp))
	if preset == Preset.CRIT:
		_attacker.stat_board.add_modifier(_set_mod(&"crit_chance", 1.0))
	var target := _nodes[target_name]
	if preset == Preset.HELD:
		_set_local(target, &"armor", held_armor)
		_set_local(target, &"min_damage_taken", 0.0)
	elif preset == Preset.GAINED:
		_set_local(target, &"armor", gained_armor)
		_set_local(target, &"min_damage_taken", gained_min_damage_taken)

	_sandbox = _SANDBOX_WORLD.new()
	_sandbox.name = "SandboxWorld"
	_world.add_child(_sandbox)
	_sandbox.build(_graph, {turn_manager = true, commands = true, attack_vfx = true})
	_battle = _sandbox.battle_system
	_battle.instant_mutation = instant
	_battle.attack_committed.connect(_on_attack_committed)
	var alloc: AllocationSystem = _sandbox.allocation_system
	_sandbox.allocation_vfx.muted = true
	for name_ in _nodes:
		alloc.force_allocate(_attacker if name_.begins_with("a_") else _defender, _nodes[name_])
	_sandbox.allocation_vfx.muted = false
	for node in _nodes.values():
		node.refill(true)
	_attacker.core_location = _nodes["a_core"]
	_defender.core_location = _nodes["d_core"]
	_sandbox.turn_manager.adopt_turn(_attacker, _sandbox.turn_manager.turns_taken)
	_layout_world()
	tooltip_mount.mount(_world, _graph)


## The node whose disc covers [param viewport_pos] (the container is 1:1 with
## the viewport), back through the board's fit transform; null for empty space.
func _pick_node_at(viewport_pos: Vector2) -> SkillNode:
	if _graph == null or not is_instance_valid(_graph):
		return null
	var local := _graph.to_local(viewport_pos)
	var best: SkillNode = null
	var best_d := INF
	for n in _graph.get_skill_nodes():
		var d := n.position.distance_to(local)
		if d <= n.radius and d < best_d:
			best = n
			best_d = d
	return best


func _add_node(node_name: String, pos: Vector2) -> SkillNode:
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	node.name = node_name
	_graph.add_skill_node(node)
	node.position = pos
	_nodes[node_name] = node
	return node


func _spawn(display_name: String, faction: Resource) -> Entity:
	var entity := Entity.new()
	entity.name = display_name
	entity.display_name = display_name
	entity.faction = faction
	entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	# entities_container: `entity_id` mints on entry there.
	_graph.entities_container.add_child(entity)
	entity.initialize()
	return entity


func _set_mod(stat_id: StringName, value: float) -> StatModifier:
	var mod := StatModifier.new()
	mod.stat_id = stat_id
	mod.operation = StatModifier.Operation.SET
	mod.value = value
	return mod


func _set_local(node: SkillNode, stat_id: StringName, value: float) -> void:
	node.add_local_modifier(_set_mod(stat_id, value))


func _on_attack_committed(outcome: AttackOutcome, _attacker_: Entity) -> void:
	_last_outcome = outcome


## An exported knob moved in the Inspector: show the new board at once.
func _rebuild_from_knob() -> void:
	if is_node_ready() and not _busy:
		_build_board(_preset_list.selected as Preset, _TARGETS[maxi(0, _target_list.selected)])


func _layout_world() -> void:
	var size := Vector2(_world.size)
	if size.x <= 0.0 or size.y <= 0.0 or _nodes.is_empty():
		return
	var bounds := Rect2(_nodes["a_core"].position, Vector2.ZERO)
	for node in _nodes.values():
		bounds = bounds.expand(node.position)
	var span := bounds.size + Vector2.ONE * (2.0 * _FIT_MARGIN)
	var factor: float = minf(1.0, minf(size.x / span.x, size.y / span.y))
	_world_host.scale = Vector2.ONE * factor
	_world_host.position = size * 0.5 - bounds.get_center() * factor


# ── Status ───────────────────────────────────────────────────────────────────

func _describe(outcome: AttackOutcome, ammo: AmmoType, preset: Preset) -> String:
	if outcome == null:
		return "[color=#ff8f6b]%s: nothing committed[/color]" % ammo.id
	var arrows := arrows_of(outcome)
	var duds := 0
	var heals := 0
	var held := 0
	var crits := 0
	for a in arrows:
		if a.gated:
			duds += 1
		elif a.kind == HitInstance.Kind.HEAL:
			heals += 1
		elif is_zero_approx(a.effective_amount):
			held += 1
		if a.is_crit:
			crits += 1
	return "[color=#8fd6ff]%s × %d · %s[/color] — dud %d · held %d · gained %d · crit %d" \
			% [ammo.id, arrows.size(), Preset.keys()[preset].capitalize(), duds, held, heals, crits]


## The arrows of a committed volley: every hit but the status riders. Not
## [method AttackOutcome.damage_hits] — that drops a hit mitigation flipped to
## a heal (rebuilt from the record as a [HealInstance]), which is exactly the
## Gained beat.
static func arrows_of(outcome: AttackOutcome) -> Array[HitInstance]:
	var out: Array[HitInstance] = []
	for hit in outcome.hits:
		if hit is DamageInstance or hit is HealInstance:
			out.append(hit)
	return out

func _refresh_status() -> void:
	if _status == null:
		return
	_status.text = _verdict if _verdict != "" else "Pick a type, a size and a preset, then Fire."
	if _fire_button != null:
		_fire_button.disabled = _busy
