@tool
extends Node2D

## #309 — the LIVE fan bench: hosts the REAL `fan.tscn` (the same scene
## [TooltipFan] mounts) over a real [SkillNode] + [Entity] fixture, and drives
## its actual inputs instead of benching a hand-rolled mock fan. The old
## `fan_trace_sandbox.gd` was a second implementation of the fan's layout that
## no test covered and nothing kept in sync; this script is a control surface,
## not a substitute — the mounted scene IS the shipped one.
##
## What lives here (mirrors the roles [TooltipFan] plays at runtime):
##   - mount + anchor: the fan instance sits at this node's origin; the
##     fixture [SkillNode] renders there too (the chip the pins ride), and
##     [member zoom] multiplies the node's radius into the driver's
##     `node_radius` — the sandbox's stand-in for camera zoom.
##   - content binding: exactly [method TooltipFan._bind_content] — every
##     [FanUnit] gets `bind(node, graph)` and `participating = has_content()`,
##     [GrantedModifiersRoot] gets `bind(node)`. Collected by group, sorted by
##     [method FanAnchorDriver.fan_sort_angle], duck-typed on
##     `play_in`/`play_out` — same member contract as the runtime coordinator.
##   - reconciliation: exactly [method TooltipFan._reconcile] — on any fixture
##     change, only the units whose participation FLIPPED play in (staggered
##     among themselves) or play out; the panels already up stay up.
##   - presets: whole-situation fixtures (unallocated / friendly / enemy /
##     core) so any occupancy the gating can produce is one click away, not a
##     boot-and-hunt in-game.
##   - drive modes: manual play-in/erase, loop, hover (distance test on the
##     fixture node + ring), a clock scrub (writes component `progress`
##     directly — the doc-blessed preview scrubber), and pointer-drag on the
##     real units (FanAnchorDriver re-routes the traces live; this supersedes
##     the old draggable [Marker2D] handles).
##
## Serialization invariants (.claude/rules/godot-workflow.md): every write this
## script makes — unit positions while dragging, `node_radius`, the clock
## knobs, addon children — lands on RUNTIME instances the panel scene instanti
## at `_ready`, never on authored scene properties, so nothing here can dirty a
## `.tscn` or `.tres`. The one exception is the fixture [SkillNode]'s addons,
## whose modifier transfer is runtime-only in `skill_node.gd` (editor-hint
## guarded), so attaching eight of them in-editor mutates no shared resource.

const _FAN_SCENE := preload("res://ui/tooltip_fan/fan.tscn")
const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _ENTITY_BOARD := preload("res://entity/default_entity_board.tres")
const _BALANCED_CORE := preload("res://entity/core/balanced_core.tres")
const _ENEMY_CORE := preload("res://entity/core/basic_enemy_core.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")
## Presets author faction by StringName id (`&"player"`/`&"npc"`) for brevity —
## no registry autoload exists, so this sandbox-local map is the resolution.
const _FACTION_BY_ID := {
	&"player": _PLAYER_FACTION,
	&"npc": _NPC_FACTION,
}

## Addon scenes the count knob draws from, cycled for counts > pool size.
## Deliberately excludes `clamp_addon.tscn` — the only one of the five that is
## `unique` (`skill_node.gd` rejects a second same-script instance with a
## `push_error`), so an 8-addon fixture needs scenes that may repeat. All real
## shipped addons — an "8-addon node" is a fixture one control away, not a
## procgen re-roll.
const _ADDON_SCENES: Array[PackedScene] = [
	preload("res://skill_node/addons/spike_ring_addon.tscn"),
	preload("res://skill_node/addons/skill_dust_addon.tscn"),
	preload("res://skill_node/addons/bunker_addon.tscn"),
	preload("res://skill_node/addons/fortification_addon.tscn"),
]

## Per-index start delay when fanning in — matches [member TooltipFan.stagger_delay].
const _STAGGER_DELAY := 0.05
const _GROUP := &"fan_unit"

const PRESET_UNALLOCATED := "unallocated" # TODO: replace with Enum
const PRESET_FRIENDLY := "friendly"
const PRESET_ENEMY := "enemy"
const PRESET_CORE := "core"

## The four whole-situation fixtures. `owned`/`core`/`addons`/`footprint` are
## the fixture knobs' values; the entity fields brand the owning [Entity] for
## the Owner/Core panels (faction flips the HOSTILE OWNER tag).
const _PRESETS: Array[Dictionary] = [
	## TODO: Replace with inner class for typing. no untyped dicts smh.
	#{
		#"name": PRESET_UNALLOCATED, "owned": false, "core": false, "addons": 0,
		#"footprint": false, "bare": true,
	#},
	#{
		#"name": PRESET_FRIENDLY, "owned": true, "core": false, "addons": 2,
		#"footprint": false, "faction": &"player", "display_name": "Dusk",
		#"core_class": _BALANCED_CORE, "level": 12, "color": Color(0.4, 0.9, 1.0),
	#},
	#{
		#"name": PRESET_ENEMY, "owned": true, "core": false, "addons": 8,
		#"footprint": false, "faction": &"npc", "display_name": "Grimjaw",
		#"core_class": _ENEMY_CORE, "level": 7, "color": Color(1.0, 0.45, 0.4),
	#},
	#{
		#"name": PRESET_CORE, "owned": true, "core": true, "addons": 8,
		#"footprint": true, "faction": &"player", "display_name": "Dusk",
		#"core_class": _BALANCED_CORE, "level": 12, "color": Color(0.4, 0.9, 1.0),
	#},
]

## A `procgen_footprint` meta shaped like the one [method GraphProcgen] stamps
## (see [ProcgenDebugPanel] for the read shape) — what makes the procgen debug
## panel light up in the bench.
const _FOOTPRINT := {
	"phase": "P4", "budget": 64, "slots": 8, "primary_slots": 4,
	"off_slots": 4, "peak_primary_cost": 12, "off_cap": 3,
	"role_tags": ["tank"],
}

enum _Mode { MANUAL, LOOP, HOVER }

## Zoom stand-in for the camera: `node_radius` fed to the fan driver is
## [member SkillNode.radius] × this. Scrubbing it is how the fan reads at every
## zoom without pinching a camera.
@export_range(0.25, 4.0, 0.05) var zoom := 1.0:
	set(value):
		zoom = value
		_apply_zoom()

## Radius (px, sandbox-local) around the fixture node that counts as "hovering"
## in hover mode — the same knob the old sandbox exposed.
@export_range(10.0, 200.0, 1.0) var hover_radius := 46.0

## Full-open dwell before the loop retracts.
@export_range(0.0, 3.0, 0.05) var hold_duration := 0.7

var _fan: Node = null
var _node: SkillNode = null
var _graph: Graph = null
var _entity: Entity = null

var _mode := _Mode.MANUAL
## Bumped by every fixture change / mode switch / scrub; a delayed play-in that
## wakes up under a stale generation bails (mirror of TooltipFan's retire /
## eligibility guards).
var _gen := 0
var _open := false
var _hovering := false
var _drag_unit: Node = null
var _grab_offset := Vector2.ZERO
var _current_preset := ""


func _ready() -> void:
	_mount_world()
	# Open on the richest preset so the tab's first look is the full six-unit
	# fan, not a bare chip.
	apply_preset(PRESET_CORE)
	set_process(true)


## Instantiates the whole bench: a small real [Graph] (fixture node + two
## off-screen neighbours so the IdChip degree reads real), the fixture
## [Entity] on a duplicated default board, and the real fan scene. Every member
## starts hidden — FanUnit/FanPanel `_ready` leave authored content visible
## under `@tool`, which is for editor authoring, not for the bench.
func _mount_world() -> void:
	_graph = _GRAPH_SCENE.instantiate() # TODO: replace with scene composition
	add_child(_graph)

	_node = _NODE_SCENE.instantiate() # TODO: replace with scene composition
	_graph.add_skill_node(_node)
	for offset in [Vector2(0, 3000), Vector2(3000, 0)]:
		var dummy := _NODE_SCENE.instantiate() # TODO: replace with scene composition
		dummy.position = offset
		_graph.add_skill_node(dummy)
		_graph.add_edge(_node, dummy)

	_entity = Entity.new()  # TODO: replace with scene composition (also prefer entity SCENE instantiate >>> Entity.new())
	_entity.stat_board = _ENTITY_BOARD.duplicate(true) as StatBoard # TODO: would already be included in Entity scene
	add_child(_entity)

	_fan = _FAN_SCENE.instantiate()  # TODO: replace with scene composition
	add_child(_fan)
	_enter_hidden_all()
	_apply_zoom()


func _process(_delta: float) -> void:
	_poll_hover()
	_poll_drag()
	if Engine.is_editor_hint():
		queue_redraw()  # keep the hover ring live in the editor viewport


# --- member collection + content binding (TooltipFan contract) ----------------

## Every fan-tier member by GROUP + duck-typed `play_in`/`play_out`, in the
## same ANGULAR order the clock pins are handed out — mirrors
## [method TooltipFan._collect_members], including [GrantedModifiersRoot].
func _members() -> Array[Node]:
	var out: Array[Node] = []
	for n in find_children("*", "", true, false):
		if n.is_in_group(_GROUP) and n.has_method(&"play_in") and n.has_method(&"play_out"):
			out.append(n)
	out.sort_custom(func(a: Node, b: Node) -> bool:
		return FanAnchorDriver.fan_sort_angle(a) < FanAnchorDriver.fan_sort_angle(b))
	return out


## Same pass TooltipFan runs on hover: bind every [FanUnit] and classify it
## (`participating = has_content()`) in one loop so the flag can never lag the
## content, and bind the ungated [GrantedModifiersRoot].
func _rebind() -> void:
	for m in _members():
		if m is FanUnit:
			var unit := m as FanUnit
			unit.bind(_node, _graph)
			unit.participating = unit.has_content()
		elif m is GrantedModifiersRoot:
			(m as GrantedModifiersRoot).bind(_node)


## Plays in/out ONLY the units whose participation changed since the last
## pass — the "panels already up stay up" rule. Newly-igniting units stagger
## among THEMSELVES, exactly like [method TooltipFan._reconcile].
func _reconcile() -> void:
	var igniting := 0
	for m in _members():
		if not (m is FanUnit):
			continue
		var unit := m as FanUnit
		var is_up: bool = unit.state == FanUnit.State.IN or unit.state == FanUnit.State.LOOP
		if unit.participating and not is_up:
			_play_in_one(unit, igniting * _STAGGER_DELAY)
			igniting += 1
		elif not unit.participating and is_up:
			unit.play_out()


## Bumped on every fixture mutation / mode switch / scrub so a delayed play-in
## from an earlier state never fires into the new one.
func _after_fixture_change() -> void:
	_gen += 1
	_rebind()
	_reconcile()


# --- presets + fixture knobs ---------------------------------------------------

static func preset_names() -> Array[String]:
	return [PRESET_UNALLOCATED, PRESET_FRIENDLY, PRESET_ENEMY, PRESET_CORE]


## Applies a whole-situation fixture, then re-derives participation from real
## `has_content()` — manual overrides are cleared by design: a preset sets the
## situation, the participation toggles fine-tune the occupancy on top.
func apply_preset(name: String) -> void:
	var spec := _preset_spec(name)
	if spec.is_empty():
		push_warning("FanLiveSandbox: unknown preset '%s'" % name)
		return
	_current_preset = name
	if spec.has("faction"):
		_entity.faction = _FACTION_BY_ID.get(spec["faction"], null)
	if spec.has("core_class"):
		_entity.core_class = spec["core_class"]
	if spec.has("display_name"):
		_entity.display_name = spec["display_name"]
	if spec.has("level"):
		_entity.level = spec["level"]
	if spec.has("color"):
		_entity.color = spec["color"]
	_entity.core_location = _node if spec.get("core", false) else null
	_node.owned_by = _entity if spec.get("owned", false) else null
	# A "bare" preset strips the node board too: the fixture node is reused
	# across presets, and its board accumulates minted stats (stake pool, HP)
	# from earlier owned/addon presets — a persistent board would make the bare
	# node gate NodeStats in when a fresh node in-game would not.
	if spec.get("bare", false) and _node.node_board != null:
		_node.node_board = null
	_set_addon_count(spec.get("addons", 0))
	_set_footprint(spec.get("footprint", false))
	_after_fixture_change()


func _preset_spec(name: String) -> Dictionary:
	for spec in _PRESETS:
		if spec["name"] == name:
			return spec
	return {}


## Fixture knobs — each is one "situation" axis; drift from a preset freely.

func set_owned(on: bool) -> void:
	_current_preset = ""
	_node.owned_by = _entity if on else null
	_after_fixture_change()


func set_core(on: bool) -> void:
	_current_preset = ""
	_entity.core_location = _node if on else null
	_after_fixture_change()


func set_addon_count(count: int) -> void:
	_current_preset = ""
	_set_addon_count(count)
	_after_fixture_change()


func _set_addon_count(count: int) -> void:
	for child in _node.get_children():
		if child is SkillNodeAddon:
			_node.remove_child(child)
			child.queue_free()
	for i in count:
		_node.add_child(_ADDON_SCENES[i % _ADDON_SCENES.size()].instantiate())


func set_footprint(on: bool) -> void:
	_current_preset = ""
	_set_footprint(on)
	_after_fixture_change()


func _set_footprint(on: bool) -> void:
	if on:
		_node.set_meta(&"procgen_footprint", _FOOTPRINT)
	else:
		_node.remove_meta(&"procgen_footprint")


## Manual participation override — reproduces any occupancy the gating can
## produce, even ones the current fixture wouldn't (e.g. Core on an unowned
## node). The panel checkboxes default to the derived values via
## [method get_participation].
func set_participating(unit_name: String, on: bool) -> void:
	for m in _members():
		if m is FanUnit and (m as FanUnit).name == unit_name:
			(m as FanUnit).participating = on
			_reconcile()
			return


func get_participation() -> Dictionary:
	var out := {}
	for m in _members():
		if m is FanUnit:
			out[(m as FanUnit).name] = (m as FanUnit).participating
	return out


func get_fixture_state() -> Dictionary:
	return {
		"owned": _node.owned_by != null,
		"core": _entity.core_location == _node,
		"addons": _node.get_addons().size(),
		"footprint": _node.has_meta(&"procgen_footprint"),
		"preset": _current_preset,
	}


# --- driver knobs (forwarded onto the mounted fan) -----------------------------

func set_zoom(v: float) -> void:
	zoom = v


func _apply_zoom() -> void:
	if _fan != null and _node != null:
		(_fan as FanAnchorDriver).node_radius = _node.radius * zoom


func set_pin_step_degrees(v: float) -> void:
	if _fan != null:
		(_fan as FanAnchorDriver).pin_step_degrees = v


func set_max_arc_degrees(v: float) -> void:
	if _fan != null:
		(_fan as FanAnchorDriver).max_arc_degrees = v


func set_pin_factor(v: float) -> void:
	if _fan != null:
		(_fan as FanAnchorDriver).pin_factor = v


func set_pin_slide_rate(v: float) -> void:
	if _fan != null:
		(_fan as FanAnchorDriver).pin_slide_rate = v


# --- drive modes (manual / loop / hover) ---------------------------------------

## ▶  Play draw-in: fan the participating members in, staggered.
func play_draw_in() -> void:
	_gen += 1
	_mode = _Mode.MANUAL
	_open = true
	_play_in_all()


## ⟲  Erase: retract every member that is up.
func play_erase() -> void:
	_gen += 1
	_mode = _Mode.MANUAL
	_open = false
	_play_out_all()


## ∞  Auto-cycle draw-in ⇄ hold ⇄ erase for continuous tuning.
func set_looping(on: bool) -> void:
	_gen += 1
	if on:
		_mode = _Mode.LOOP
		_open = true
		_loop_cycle()
	else:
		_mode = _Mode.MANUAL


## ☌  Hover-driven opening: fan in while the pointer is within `hover_radius`
## of the fixture node, retract on leave. Reads the viewport mouse directly
## (distance test) — no physics picking, which is unreliable in an embedded
## editor SubViewport.
func set_hover_driven(on: bool) -> void:
	_gen += 1
	_mode = _Mode.HOVER if on else _Mode.MANUAL
	_open = false
	if not on:
		_play_out_all()


## ■  Reset to settled-open: everything hidden, then fanned in.
func reset_settled() -> void:
	_gen += 1
	_mode = _Mode.MANUAL
	_open = true
	_enter_hidden_all()
	_play_in_all()


## Clock scrub — writes each participating member's component `progress`
## directly (the preview scrubber `docs/domain/tooltip-fan.md` blesses; not the
## shipped drive model). Mutually exclusive with the animated modes: activating
## it drops back to MANUAL.
func set_scrub(t: float) -> void:
	_gen += 1
	_mode = _Mode.MANUAL
	_open = false
	for m in _members():
		if not (m is FanUnit):
			continue
		var unit := m as FanUnit
		if not unit.participating:
			continue
		var trace: FanTrace = unit.get_node_or_null("%Trace")
		if trace != null:
			trace.progress = t
		var panel: FanPanel = unit.get_node_or_null("%Panel")
		if panel != null:
			panel.progress = t


## Fires every participating member with an increasing per-index delay —
## the "fire N units, each with its own delay" coordinator behaviour. Members
## already up are left alone so a loop cycle never restarts a settled panel.
func _play_in_all() -> void:
	var index := 0
	for m in _members():
		if m is FanUnit:
			var unit := m as FanUnit
			if not unit.participating or unit.state != FanUnit.State.HIDDEN:
				continue
		elif m.visible:
			continue
		_play_in_one(m, index * _STAGGER_DELAY)
		index += 1


func _play_in_one(member: Node, delay: float) -> void:
	var gen := _gen
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
		if gen != _gen or not is_instance_valid(member):
			return
	if member is FanUnit and not (member as FanUnit).participating:
		return
	member.play_in()


## Retracts every member in parallel — the OUT sequences run concurrently.
func _play_out_all() -> void:
	for m in _members():
		if m is FanUnit:
			if (m as FanUnit).state == FanUnit.State.HIDDEN:
				continue
		elif not m.visible:
			continue
		m.play_out()


func _enter_hidden_all() -> void:
	for m in _members():
		if m.has_method(&"enter_hidden"):
			m.enter_hidden()


func _loop_cycle() -> void:
	while _mode == _Mode.LOOP:
		_play_in_all()
		await get_tree().create_timer(hold_duration).timeout
		if _mode != _Mode.LOOP:
			return
		_play_out_all()
		await get_tree().create_timer(hold_duration).timeout


func _poll_hover() -> void:
	if _mode != _Mode.HOVER:
		return
	var hovering := get_local_mouse_position().length() <= hover_radius
	if hovering != _hovering:
		_hovering = hovering
		queue_redraw()
	if hovering and not _open:
		_open = true
		_play_in_all()
	elif not hovering and _open:
		_open = false
		_play_out_all()


# --- pointer drag on the real units -------------------------------------------

## Drags a real [FanUnit] — `FanAnchorDriver` re-derives both trace endpoints
## from the panel's live position every frame, so the line follows without any
## of the old mock's Marker2D handles. Polled, not event-driven, so it works
## inside an embedded editor SubViewport (the same reason hover uses a
## distance test).
func _poll_drag() -> void:
	var mp := get_local_mouse_position()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if _drag_unit == null:
			var hit := hit_test(mp)
			if hit != null:
				_drag_unit = hit
				_grab_offset = mp - (hit as Node2D).position
		if _drag_unit != null and is_instance_valid(_drag_unit):
			(_drag_unit as Node2D).position = mp - _grab_offset
	else:
		_drag_unit = null


## Which [FanUnit]'s panel rect contains `p` (sandbox-local space) — visible
## units only, so a gated-out panel can't be grabbed.
func hit_test(p: Vector2) -> Node:
	for m in _members():
		if not (m is FanUnit):
			continue
		var unit := m as FanUnit
		if not unit.visible:
			continue
		var panel: FanPanel = unit.get_node_or_null("%Panel")
		if panel == null:
			continue
		var rect := FanAnchor.panel_rect_of(panel)
		rect.position += (unit as Node2D).position
		if rect.has_point(p):
			return unit
	return null


func _draw() -> void:
	if _mode == _Mode.HOVER:
		var ring := Color(0.7, 1.0, 1.0, 0.18 if _hovering else 0.08)
		draw_arc(Vector2.ZERO, hover_radius, 0.0, TAU, 64, ring, 1.0, true)
