@tool
extends PanelContainer

## Allocation / deallocation / death VFX LIVE panel (#260) — the played
## showcase's heir. A 3×3 grid of self-resetting "animation cells", each
## looping a single allocation-flavoured scenario against the REAL systems
## (AllocationSystem + BattleSystem + AllocationVFX + FloaterToasterManager).
## Because it drives the genuine `allocate` / `deallocate` / `force_deallocate` /
## `take_damage` paths, the #71 modifier pulses and #70 floaters fire for real.
##
## How it's live (the "auto-tick = played; explicit-step = live" kernel from
## sandbox-framework.md): the systems are @tool and the panel runs them
## in-editor, but NOTHING auto-drives. The old showcase ran a `_process` +
## `await create_timer` SETUP→PLAY loop on an infinite cycle; here the beat is
## one explicit click of ▶ Play beat (and ⟲ Reset for a setup-only pass).
## No `_process` label polling either — labels refresh on demand at the end of
## each beat. The TurnManager is never involved, so the "never tick it in the
## editor" guardrail is trivially held.
##
## The world renders in a SubViewport (SubViewportContainer stretch=true), so
## container pixels ARE world pixels: the 3×3 grid is laid out against the
## viewport's live size (spell-playground pattern), no camera needed.
##
## Each cell renders its entity's live STRENGTH so you can eyeball the gap
## between the *resolved* gameplay value (updates synchronously on allocate)
## and the *visual* catching up (pulses/floaters arrive later). That lag is
## the point.

const _SKILL_NODE_SCENE: PackedScene = preload("res://skill_node/skill_node.tscn")
const _SANDBOX_WORLD: Script = preload("res://scenes/dev/sandbox_world.gd")
const _DEFAULT_BOARD: Resource = preload("res://entity/default_entity_board.tres")

# --- Tunables (inspector-designable on the panel scene) ----------------------
@export var setup_hold: float = 1.1        ## SETUP beat duration (s)
@export var play_hold: float = 4.2         ## PLAY beat duration (s) — must exceed the longest scenario
@export var bulk_stagger: float = 0.18     ## s between successive allocations in the bulk-alloc cell
@export var str_per_node: float = 5.0      ## STR each owned node grants
@export var sp_base: float = 20.0          ## SP floor re-established every reset (kept high so play never underflows)

# --- Runtime refs ------------------------------------------------------------
@onready var graph: Graph = %Graph          ## The embedded world's graph (test/driver hook)
var _alloc: AllocationSystem
var _battle: BattleSystem
var _vfx: AllocationVFX
var _floaters: FloaterToasterManager
var _cells: Array[_Cell] = []
var _busy: bool = false

@onready var _play_button: Button = %PlayBeatBtn
@onready var _reset_button: Button = %ResetBtn
@onready var _beat_label: Label = %BeatLabel
@onready var _world: SubViewport = %World


## The SandboxLiveTab loader hook. Self-contained — nothing to route in.
func load_object(_obj: Object) -> void:
	pass


func _ready() -> void:
	_play_button.pressed.connect(play_beat)
	_reset_button.pressed.connect(reset_world)
	_world.size_changed.connect(_layout_world)
	_build_systems()
	_build_grid()
	_layout_world()
	# Present the grid ARMED (each cell's initial owned set, muted) so the
	# scenario topologies are visible before the first beat.
	reset_world()


# --- Composition -------------------------------------------------------------

## Compose systems via the shared SandboxWorld scaffold (mirrors GameRoot's
## wiring). This bench needs only the allocation core — no TurnManager / Loot /
## Vision / UI — so it requests the default subset.
func _build_systems() -> void:
	var world = _SANDBOX_WORLD.new()
	world.name = "SandboxWorld"
	_world.add_child(world)
	world.build(graph)
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
	cell.row = row
	cell.col = col
	cell.core_index = _core_index_for(kind)
	var n_count: int = 1 if kind in ["alloc_single", "dealloc_single", "death_single"] else 5

	# Nodes (instantiate the real scene — honours the SkillNode contract).
	for j in n_count:
		var node: SkillNode = _SKILL_NODE_SCENE.instantiate()
		node.base_type_color = color.darkened(0.3)
		# Every node carries a STR modifier so allocation visibly moves STR; the
		# modifier-travel target carries three (→ three staggered pulses).
		var mods: Array[StatModifier] = []
		var mod_count: int = 3 if (kind == "alloc_travel" and j == 0) else 1
		for _k in mod_count:
			mods.append(_str_mod(str_per_node))
		node.modifiers = mods
		graph.add_skill_node(node)
		cell.nodes.append(node)

	# Edges: chain consecutive nodes (single-node cells have none).
	for j in range(cell.nodes.size() - 1):
		graph.add_edge(cell.nodes[j], cell.nodes[j + 1])

	# Entity (one per cell → its own EntityNavigator). Parented under the graph's
	# Entities container so Entity._ready auto-creates the navigator.
	cell.entity = Entity.new()
	cell.entity.name = "Owner_%d_%d" % [row, col]
	cell.entity.display_name = cell.entity.name
	cell.entity.color = color
	cell.entity.stat_board = _DEFAULT_BOARD.duplicate(true) as StatBoard
	graph.entities_container.add_child(cell.entity)

	# Per-cell live label (world-space; scales with the panel).
	cell.label = Label.new()
	cell.label.add_theme_font_size_override("font_size", 15)
	_world.add_child(cell.label)
	return cell


# --- World layout ------------------------------------------------------------

## Lay the 3×3 grid out against the viewport's live size (SubViewportContainer
## stretch=true → viewport pixels ARE panel pixels). Cell pitch tracks the
## smaller axis so the grid never overflows; node spacing scales with it.
func _layout_world() -> void:
	var size := _world.size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var margin := 40.0
	var pitch := minf((size.x - 2.0 * margin) / 3.0, (size.y - 2.0 * margin) / 3.0)
	var node_spacing := pitch * 0.18
	var origin := Vector2((size.x - 2.0 * pitch) * 0.5, (size.y - 2.0 * pitch) * 0.5)
	for cell in _cells:
		var grid_pos := origin + Vector2(cell.col * pitch, cell.row * pitch)
		for j in cell.nodes.size():
			cell.nodes[j].position = grid_pos + Vector2(j * node_spacing, 0.0)
		if cell.label != null:
			cell.label.position = grid_pos + Vector2(-node_spacing, -pitch * 0.36)
	for e in graph.get_edges():
		e.refresh_endpoints()


# --- Beats (explicit triggers — nothing auto-runs) ----------------------------

## One full SETUP→PLAY cycle: silently re-arm every cell (muted cosmetics),
## then run all nine scenarios concurrently. The loop the played showcase ran
## on an infinite `_process` cycle is now exactly one button press.
func play_beat() -> void:
	if _busy or _cells.is_empty():
		return
	_busy = true
	_set_controls_enabled(false)

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

	_beat_label.text = "idle — ready"
	_refresh_labels()
	_busy = false
	_set_controls_enabled(true)


## Setup beat only — re-arm every cell to its armed state without playing.
## Synchronous (the full-cycle dust-clearing race is a loot-panel concern).
func reset_world() -> void:
	if _busy:
		return
	_begin_setup()
	for cell in _cells:
		_setup_cell(cell)
	_end_setup()
	_beat_label.text = "armed"
	_refresh_labels()


## Mute cosmetics for the SETUP beat: the silent reset below drives the REAL
## force_deallocate / force_allocate primitives (full fidelity), which would
## otherwise spew shatters + spikes. `AllocationVFX.muted` early-returns the
## handlers so nothing spawns at all. Floaters need no muting: setup does no
## take_damage, so none fire.
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


func _refresh_labels() -> void:
	for cell in _cells:
		if cell.label == null or cell.entity == null or cell.entity.stat_board == null:
			continue
		var str_val: Variant = cell.entity.stat_board.get_value(&"strength")
		cell.label.text = "%s\nSTR %d" % [cell.title, int(str_val) if str_val != null else 0]


func _set_controls_enabled(enabled: bool) -> void:
	_play_button.disabled = not enabled
	_reset_button.disabled = not enabled


func _sleep(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# --- Cell record -------------------------------------------------------------

class _Cell:
	var kind: String
	var title: String
	var row: int
	var col: int
	var nodes: Array[SkillNode] = []
	var core_index: int = -1
	var entity: Entity
	var label: Label
