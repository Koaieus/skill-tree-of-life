extends Node2D

## Allocation / deallocation / death VFX showcase — a 3×3 grid of self-resetting
## "animation cells", each looping a single allocation-flavoured scenario against
## the REAL systems (AllocationSystem + BattleSystem + AllocationVFX +
## FloaterToasterManager). Because it drives the genuine `allocate` / `deallocate` /
## `force_deallocate` / `take_damage` paths, the #71 modifier pulses and #70
## floaters fire for real — the old playground faked the signals and so couldn't.
##
## Why code-generated (not a hand-authored 30-node .tscn): the grid is regular
## and procedural (procgen-shaped). The `.tscn` instances the real `graph.tscn`
## (so the Graph/Navigator/containers contract is honoured) + a Camera; the cells,
## entities and systems are composed here. Systems are wired exactly as
## `GameRoot._ready` wires them — that's the fidelity contract that makes this a
## trustworthy preview rather than a drifting copy.
##
## Beat model (user spec): the whole grid runs two global beats on a loop —
## SETUP (silently reset every cell to its armed state) → PLAY (every cell runs
## its scenario at once) → SETUP → PLAY → … Setup cosmetics are muted (see
## `_begin_setup`) so only the PLAY beat shows VFX.
##
## Each cell renders its entity's live STRENGTH so you can eyeball the gap
## between the *resolved* gameplay value (updates synchronously on allocate) and
## the *visual* catching up (pulses/floaters arrive later). That lag is the point.

const _SKILL_NODE_SCENE: PackedScene = preload("res://skill_node/skill_node.tscn")
const _SANDBOX_WORLD: Script = preload("res://scenes/dev/sandbox_world.gd")
const _DEFAULT_BOARD: Resource = preload("res://entity/default_entity_board.tres")

# --- Tunables (inspector-designable) ----------------------------------------
@export var col_spacing: float = 520.0     ## px between cell columns
@export var row_spacing: float = 240.0     ## px between cell rows
@export var node_spacing: float = 92.0     ## px between nodes within a cell
@export var setup_hold: float = 1.1        ## SETUP beat duration (s)
@export var play_hold: float = 4.2         ## PLAY beat duration (s) — must exceed the longest scenario
@export var bulk_stagger: float = 0.18     ## s between successive allocations in the bulk-alloc cell
@export var str_per_node: float = 5.0      ## STR each owned node grants
@export var sp_base: float = 20.0          ## SP floor re-established every reset (kept high so play never underflows)

# --- Runtime refs ------------------------------------------------------------
var _graph: Graph
var _alloc: AllocationSystem
var _battle: BattleSystem
var _vfx: AllocationVFX
var _floaters: FloaterToasterManager
var _cells: Array[_Cell] = []
var _beat_label: Label


func _ready() -> void:
	_graph = $Graph
	_build_systems()
	_build_grid()
	_build_camera()
	_build_beat_label()
	_run_loop()


# --- Composition -------------------------------------------------------------

## Compose systems via the shared SandboxWorld scaffold (mirrors GameRoot's
## wiring). This bench needs only the allocation core — no TurnManager / Loot /
## Vision / UI — so it requests the default subset.
func _build_systems() -> void:
	var world = _SANDBOX_WORLD.new()
	world.name = "SandboxWorld"
	add_child(world)
	world.build(_graph)
	_alloc = world.allocation_system
	_battle = world.battle_system
	_vfx = world.allocation_vfx
	_floaters = world.floating_number_layer


## The 3×3 scenario table. Topology key: O = unallocated, 0 = allocated,
## X = allocated core. Left→right is node index 0→n-1.
func _build_grid() -> void:
	var specs := [
		# row, col, kind,                 title
		[0, 0, "alloc_single",        "O  · allocate"],
		[0, 1, "dealloc_single",      "O  · deallocate"],
		[0, 2, "death_single",        "O  · force-dealloc (shatter)"],
		[1, 0, "alloc_travel",        "O-0-0-0-X · allocate → 3 mods travel"],
		[1, 1, "bulk_alloc",          "X-O-O-O-O · bulk allocate from core"],
		[1, 2, "dealloc_first",       "0-0-0-0-X · deallocate first"],
		[2, 0, "force_dealloc_first", "0-0-0-0-X · force-dealloc first"],
		[2, 1, "cascade_mid",         "0-0-0-0-X · force-dealloc 4th → cascade"],
		[2, 2, "core_death",          "0-0-0-0-X · core death → cascade"],
	]
	var palette := [
		Color(0.40, 0.80, 1.00), Color(1.00, 0.70, 0.40), Color(0.70, 1.00, 0.55),
		Color(0.85, 0.65, 1.00), Color(1.00, 0.85, 0.45), Color(0.55, 0.90, 0.90),
		Color(1.00, 0.55, 0.55), Color(0.65, 0.80, 1.00), Color(1.00, 0.50, 0.80),
	]
	for i in specs.size():
		var spec: Array = specs[i]
		_cells.append(_make_cell(spec[0], spec[1], spec[2], spec[3], palette[i]))


func _make_cell(row: int, col: int, kind: String, title: String, color: Color) -> _Cell:
	var cell := _Cell.new()
	cell.kind = kind
	cell.title = title
	cell.core_index = _core_index_for(kind)
	var n_count: int = 1 if kind in ["alloc_single", "dealloc_single", "death_single"] else 5
	var origin := Vector2(col * col_spacing, row * row_spacing)

	# Nodes (instantiate the real scene — honours the SkillNode contract).
	for j in n_count:
		var node: SkillNode = _SKILL_NODE_SCENE.instantiate()
		node.position = origin + Vector2(j * node_spacing, 0.0)
		node.base_type_color = color.darkened(0.3)
		# Every node carries a STR modifier so allocation visibly moves STR; the
		# modifier-travel target carries three (→ three staggered pulses).
		var mods: Array[StatModifier] = []
		var mod_count: int = 3 if (kind == "alloc_travel" and j == 0) else 1
		for _k in mod_count:
			mods.append(_str_mod(str_per_node))
		node.modifiers = mods
		_graph.add_skill_node(node)
		cell.nodes.append(node)

	# Edges: chain consecutive nodes (single-node cells have none).
	for j in range(cell.nodes.size() - 1):
		_graph.add_edge(cell.nodes[j], cell.nodes[j + 1])

	# Entity (one per cell → its own EntityNavigator). Parented under the graph's
	# Entities container so Entity._ready auto-creates the navigator.
	cell.entity = Entity.new()
	cell.entity.name = "Owner_%d_%d" % [row, col]
	cell.entity.display_name = cell.entity.name
	cell.entity.color = color
	cell.entity.stat_board = _DEFAULT_BOARD.duplicate(true) as StatBoard
	_graph.entities_container.add_child(cell.entity)

	# Per-cell live label (world-space; scales with the camera).
	cell.label = Label.new()
	cell.label.position = origin + Vector2(-24.0, -86.0)
	cell.label.add_theme_font_size_override("font_size", 15)
	add_child(cell.label)
	return cell


func _build_camera() -> void:
	var cam := $Camera2D as Camera2D
	if cam == null:
		return
	# Frame the whole grid: centre on its midpoint, zoom out to fit.
	var last_col := 2.0
	var last_row := 2.0
	var span := Vector2(last_col * col_spacing + 4.0 * node_spacing, last_row * row_spacing)
	cam.position = span * 0.5
	cam.zoom = Vector2(0.62, 0.62)
	cam.make_current()


func _build_beat_label() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_beat_label = Label.new()
	_beat_label.position = Vector2(24, 16)
	_beat_label.add_theme_font_size_override("font_size", 22)
	layer.add_child(_beat_label)


# --- Beat loop ---------------------------------------------------------------

func _run_loop() -> void:
	while is_inside_tree():
		_begin_setup()
		for cell in _cells:
			_setup_cell(cell)
		_end_setup()
		_beat_label.text = "SETUP"
		await _sleep(setup_hold)

		_beat_label.text = "PLAY"
		for cell in _cells:
			# Fire-and-forget: each scenario is its own coroutine so all cells
			# play concurrently. play_hold must outlast the longest one.
			_play_cell(cell)
		await _sleep(play_hold)


## Mute cosmetics for the SETUP beat: the silent reset below drives the REAL
## force_deallocate / force_allocate primitives (full fidelity), which would
## otherwise spew shatters + spikes. `AllocationVFX.muted` early-returns the
## handlers so nothing spawns at all — cleaner than hiding/freeing transient
## children (their tweens live on the long-lived VFX node, not the children).
## Floaters need no muting: setup does no take_damage, so none fire.
func _begin_setup() -> void:
	_vfx.muted = true


func _end_setup() -> void:
	_vfx.muted = false


func _setup_cell(cell: _Cell) -> void:
	var e := cell.entity
	# Silent teardown: strip whatever it still owns (real primitive, muted VFX).
	for n in cell.nodes:
		if n.owned_by == e:
			_alloc.force_deallocate(n)
	e.is_dead = false          # core_death latches this; clear so it re-fires next cycle
	_reset_board(e)
	e.core_location = null
	# Re-arm: force_allocate the cell's initial owned set (claims SP itself).
	var owned := _initial_owned_indices(cell)
	for idx in owned:
		_alloc.force_allocate(e, cell.nodes[idx])
	if cell.core_index >= 0 and owned.has(cell.core_index):
		e.core_location = cell.nodes[cell.core_index]


## Run a cell's scenario against the real systems. Each is the genuine gameplay
## call — the VFX/floaters are downstream of the systems, never faked here.
func _play_cell(cell: _Cell) -> void:
	var e := cell.entity
	match cell.kind:
		"alloc_single", "alloc_travel":
			_alloc.allocate(cell.nodes[0], e)
		"dealloc_single", "dealloc_first":
			_alloc.deallocate(cell.nodes[0], e)
		"death_single":
			_alloc.force_deallocate(cell.nodes[0])
		"bulk_alloc":
			for j in range(1, cell.nodes.size()):
				_alloc.allocate(cell.nodes[j], e)
				await _sleep(bulk_stagger)
		"force_dealloc_first":
			cell.nodes[0].take_damage(99999.0, null)
		"cascade_mid":
			cell.nodes[3].take_damage(99999.0, null)   # 4th node; islands 3rd..1st
		"core_death":
			cell.nodes[cell.core_index].take_damage(999999.0, null)  # overflow → health → die


# --- Per-kind config ---------------------------------------------------------

func _core_index_for(kind: String) -> int:
	match kind:
		"alloc_single", "dealloc_single", "death_single":
			return -1
		"bulk_alloc":
			return 0    # X-O-O-O-O
		_:
			return 4    # …-X (core on the right)


func _initial_owned_indices(cell: _Cell) -> Array[int]:
	match cell.kind:
		"alloc_single":
			return []
		"dealloc_single", "death_single":
			return [0]
		"alloc_travel":
			return [1, 2, 3, 4]              # all but the target (0)
		"bulk_alloc":
			return [0]                       # core only
		_:
			return [0, 1, 2, 3, 4]           # fully allocated


# --- Helpers -----------------------------------------------------------------

func _reset_board(e: Entity) -> void:
	var b := e.stat_board
	if b == null:
		return
	if b.skill_points != null:
		b.skill_points.wounded = 0
		b.skill_points.staked = 0
		b.skill_points.base_value = sp_base
		b.skill_points.set_current(sp_base)
	if b.health != null:
		b.health.restore_to_full()
	if b.deallocation_points != null:
		b.deallocation_points.restore_to_full()
	if b.action_points != null:
		b.action_points.restore_to_full()


func _str_mod(v: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = &"strength"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = v
	return m


func _process(_dt: float) -> void:
	for cell in _cells:
		if cell.label == null or cell.entity == null or cell.entity.stat_board == null:
			continue
		var str_val: Variant = cell.entity.stat_board.get_value(&"strength")
		cell.label.text = "%s\nSTR %d" % [cell.title, int(str_val) if str_val != null else 0]


func _sleep(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# --- Cell record -------------------------------------------------------------

class _Cell:
	var kind: String
	var title: String
	var nodes: Array[SkillNode] = []
	var core_index: int = -1
	var entity: Entity
	var label: Label
