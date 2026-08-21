@tool
extends PanelContainer

## Melee sandbox — swing real blades in the editor (#256).
##
## The world is `scenes/dev/melee_sandbox_graph.tscn`: fifteen hand-authored
## nodes for the wielder (a hilt, a spine that reads as a blade, two prongs and a
## lower arm) and a five-node quarry with spikes on two of them, so the pop path
## fires. **Every position is authored** — this panel only centres and scales the
## authored layout to the panel, and turns each node's authored `owned_by` into a
## real `force_allocate` (ownership can't be authored: the per-entity mirror is
## populated by [AllocationSystem], never scanned off the scene).
##
## [b]Live, not played.[/b] The systems are the real ones and every beat is an
## explicit click — pick a pivot, grow the blade, Launch — which is the
## "auto-tick = played; explicit-step = live" line in `sandbox-framework.md`. The
## single exception is [MeleePreview]'s idle ghost loop, which genuinely does
## auto-drive a swing sim; it is switched off (with the whole SubViewport) the
## moment the tab loses focus, so nothing crunches behind a hidden panel.
##
## [b]Clicks are hand-picked.[/b] Physics picking through an editor-hosted
## SubViewport is unreliable (the spell playground found this and does the same),
## so the container hit-tests and hands the node to
## [method PlayerInputController.route_left_click] — the real channel order, just
## a different carrier. Right-click is [method AttackPlan.pop], the shared
## primitive behind the click grammar.
##
## [b]No cooldown.[/b] AP is refilled and (optionally) the same selection is
## re-armed the instant a swing ends, so Launch is clickable again immediately.
## The floor on "swings per second" is [constant MeleeAttackPlan.SWING_DURATION]
## and [member BattleSystem.is_launching], which serialises swings — one blade in
## flight at a time, by design. Overlapping swings would need a second launch
## path, and a sandbox that doesn't run the real one proves nothing.

## Emitted for [SandboxLiveTab]'s Reload button (#144) — a hard reset for a world
## that got wedged (a stuck launch, a corpse cascade you want undone).
signal reload_requested

const _WORLD_SCENE: PackedScene = preload("res://scenes/dev/melee_sandbox_graph.tscn")
const _SANDBOX_WORLD: Script = preload("res://scenes/dev/sandbox_world.gd")
const _MELEE_BODY_SCENE: PackedScene = preload("res://ui/hud/command_tray/bodies/melee_body.tscn")
const _DEFAULT_STYLE: BladeStyle = preload("res://attack/melee/default_blade_style.tres")

## Room left around the authored layout when it is fitted to the panel.
const _FIT_MARGIN: float = 40.0

## Style knobs, generated into `%StyleKnobs`: property, label, min, max, step.
## Same table shape the bloom panel uses for the Environment — one row per thing
## worth turning, so adding a [BladeStyle] field is a one-line change here.
const _KNOBS: Array[Array] = [
	["entity_tint", "Wielder tint", 0.0, 1.0, 0.01],
	["rim_tier", "Rim tier (EV)", -2.0, 4.0, 0.05],
	["rim_width", "Rim width", 0.5, 12.0, 0.5],
	["fill_tier", "Fill tier (EV)", -2.0, 4.0, 0.05],
	["fill_alpha", "Fill alpha", 0.0, 1.0, 0.01],
	["edge_tier", "Edge tier (EV)", -2.0, 4.0, 0.05],
	["edge_width", "Edge width", 0.5, 12.0, 0.5],
	["disabled_tier", "Popped tier (EV)", -3.0, 2.0, 0.05],
	["disabled_desaturation", "Popped desaturation", 0.0, 1.0, 0.01],
	["disabled_alpha", "Popped alpha", 0.0, 1.0, 0.01],
]

@onready var _world: SubViewport = %World
@onready var _world_container: SubViewportContainer = %WorldContainer
@onready var graph: Graph = %Graph            ## The authored world (test hook).
@onready var _tray_host: Control = %TrayHost
@onready var _blade_size: SpinBox = %BladeSizeSpin
@onready var _delit_spin: SpinBox = %DelitSpin
@onready var _preview_toggle: CheckBox = %PreviewToggle
@onready var _immortal_toggle: CheckBox = %ImmortalToggle
@onready var _rearm_toggle: CheckBox = %RearmToggle
@onready var _reset_button: Button = %ResetBtn
@onready var _status: Label = %StatusLabel
@onready var _knob_box: VBoxContainer = %StyleKnobs

var _wielder: Entity
var _quarry: Entity
var _alloc: AllocationSystem
var _battle: BattleSystem
var _input: PlayerInputController
var _preview: MeleePreview
var _tray: CommandTrayBodyBase

## The style every blade in this world draws from. Starts as a working COPY of
## `default_blade_style.tres` so knob-twiddling here can't silently rewrite the
## shipped resource; inspecting a BladeStyle routes that one in instead.
var _style: BladeStyle

## Authored ownership, captured once before anything is re-allocated — `owned_by`
## in the .tscn is the DECLARATION, `force_allocate` is what makes it true.
var _authored_owner: Dictionary = {}
## World-space bounds of the authored layout, for the fit transform.
var _authored_bounds: Rect2
## Pivot + members of the last launched swing, replayed by auto re-arm.
var _last_selection: Array[SkillNode] = []


func _ready() -> void:
	_style = _DEFAULT_STYLE.duplicate(true) as BladeStyle
	_build_systems()
	_capture_authored_state()
	_build_knobs()
	_wire_controls()
	_mount_tray()
	arm_world()
	_layout_world()
	_world.size_changed.connect(_layout_world)
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


## Sandbox-host contract. A [BladeStyle] selected in the Inspector becomes the
## live style for this world, so the tab doubles as its editing surface.
func load_object(obj: Object) -> void:
	if obj is BladeStyle:
		set_style(obj as BladeStyle)


# ── Composition ──────────────────────────────────────────────────────────────

## Real systems through the shared scaffold, mirroring GameRoot's wiring. Melee
## needs more of the game than the other live panels: a MeleePreview (nothing
## draws a swing without it), a CommandApplier (an attack is a command since
## #511), an input controller (the click channels) and a TurnManager (whose
## `current_entity` is the only thing that says an attack is legal at all).
func _build_systems() -> void:
	var world = _SANDBOX_WORLD.new()
	world.name = "SandboxWorld"
	_world.add_child(world)
	world.build(graph, {melee = true, input = true})
	_alloc = world.allocation_system
	_battle = world.battle_system
	_input = world.input_controller
	_preview = world.melee_preview
	_battle.attack_plan_changed.connect(_on_plan_changed)


## Snapshot what the .tscn declares, before the panel starts mutating it.
func _capture_authored_state() -> void:
	var nodes := graph.get_skill_nodes()
	for n in nodes:
		_authored_owner[n] = n.owned_by
	_authored_bounds = Rect2(nodes[0].position, Vector2.ZERO) if not nodes.is_empty() else Rect2()
	for n in nodes:
		_authored_bounds = _authored_bounds.expand(n.position)
	for entity in [_entity_named("Wielder"), _entity_named("Quarry")]:
		if entity != null:
			# The editor never runs `_ready`, so an authored entity is inert
			# until someone says otherwise — board, intrinsics, navigator.
			entity.initialize()
	_wielder = _entity_named("Wielder")
	_quarry = _entity_named("Quarry")


func _entity_named(n: String) -> Entity:
	return graph.entities_container.get_node_or_null(NodePath(n)) as Entity


func _mount_tray() -> void:
	_tray = _MELEE_BODY_SCENE.instantiate() as CommandTrayBodyBase
	_tray_host.add_child(_tray)
	_tray.bind(_wielder, _battle, _input)


# ── World state ──────────────────────────────────────────────────────────────

## Re-arm the world: strip every claim, refill the boards, re-apply the authored
## ownership through the real primitive, hand the turn to the wielder and put a
## fresh melee plan up. This is the panel's only "reset" — it runs at startup too,
## so the state you see on open is the state Reset gives you.
func arm_world() -> void:
	if _battle.is_launching:
		return
	_battle.cancel_attack()
	_last_selection.clear()
	for n in graph.get_skill_nodes():
		if n.owned_by != null:
			_alloc.force_deallocate(n)
		n.refill(true)
	for entity in [_wielder, _quarry]:
		_reset_board(entity)
		entity.is_dead = false
	for n in graph.get_skill_nodes():
		var owner_entity: Entity = _authored_owner.get(n)
		if owner_entity != null:
			_alloc.force_allocate(owner_entity, n)
	_wielder.core_location = _node_named("Hilt")
	_quarry.core_location = _node_named("E_Core")
	# TurnManager is never TICKED here (the standing editor rule) — `current_entity`
	# is a plain var, and writing it is the whole of "it's the wielder's turn".
	_battle.turn_manager.current_entity = _wielder
	_battle.request_attack_mode(BattleSystem.AttackMode.MELEE)
	_apply_blade_size()
	_refresh_status()


func _node_named(n: String) -> SkillNode:
	return graph.skill_nodes_container.get_node_or_null(NodePath(n)) as SkillNode


func _reset_board(entity: Entity) -> void:
	var b: StatBoard = entity.stat_board if entity != null else null
	if b == null:
		return
	if b.skill_points != null:
		b.skill_points.wounded = 0
		b.skill_points.staked = 0
		b.skill_points.base_value = 60.0
		b.skill_points.set_current(60.0)
	for pool in [b.health, b.action_points, b.deallocation_points, b.mana]:
		if pool != null:
			pool.restore_to_full()


# ── Layout ───────────────────────────────────────────────────────────────────

## Fit the AUTHORED layout to the panel — centre it, and shrink it if the panel
## is smaller than the layout. Never moves a node: the transform lives on the
## Graph, so authored positions stay the single source of truth (and the blade,
## which reads `global_position`, follows the transform for free).
func _layout_world() -> void:
	var size := Vector2(_world.size)
	if size.x <= 0.0 or size.y <= 0.0 or _authored_bounds.size == Vector2.ZERO:
		return
	var span := _authored_bounds.size + Vector2.ONE * (2.0 * _FIT_MARGIN)
	var scale_factor: float = minf(1.0, minf(size.x / span.x, size.y / span.y))
	graph.scale = Vector2.ONE * scale_factor
	graph.position = size * 0.5 - _authored_bounds.get_center() * scale_factor


# ── Input ────────────────────────────────────────────────────────────────────

func _on_world_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	var hit := _pick_node_at(graph.to_local(mb.position))
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if hit != null:
			_input.route_left_click(hit)
			_world_container.accept_event()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		# One level off whichever plan is armed — the same primitive right-click
		# pops in-game, minus the armed-mode stack this panel doesn't run.
		if _battle.attack_plan != null:
			_battle.attack_plan.pop()
			_world_container.accept_event()
	_refresh_status()


func _pick_node_at(world_pos: Vector2) -> SkillNode:
	var best: SkillNode = null
	var best_d := INF
	for n in graph.get_skill_nodes():
		var d := n.position.distance_to(world_pos)
		if d <= n.radius and d < best_d:
			best = n
			best_d = d
	return best


# ── Controls ─────────────────────────────────────────────────────────────────

func _wire_controls() -> void:
	_world_container.gui_input.connect(_on_world_gui_input)
	_reset_button.pressed.connect(arm_world)
	_blade_size.value_changed.connect(_on_blade_size_changed)
	_delit_spin.value_changed.connect(_on_delit_changed)
	_preview_toggle.toggled.connect(_on_preview_toggled)
	_rearm_toggle.toggled.connect(func(_on: bool) -> void: _refresh_status())
	Events.skill_node_damaged.connect(_on_node_damaged)


func _on_blade_size_changed(_value: float) -> void:
	_apply_blade_size()
	_refresh_status()


## `blade_size` is an ordinary board scalar, so the knob is a plain base write —
## no pool, no ratchet (`.claude/rules/stat-knobs-and-bins.md`). `max_blades()`
## reads it node-locally off the pivot, so this lands on the next plan refresh.
func _apply_blade_size() -> void:
	var board: EntityStatBoard = _wielder.stat_board as EntityStatBoard
	if board != null and board.blade_size != null:
		board.blade_size.base_value = _blade_size.value


func _on_preview_toggled(on: bool) -> void:
	_preview.preview_enabled = on
	_refresh_status()


## Force the outermost N vertices of the LIVE ghost de-lit, for tuning the look
## without waiting to be popped. A real swing overwrites this from
## [member SkillBlade.pop_result] — the model always wins.
func _on_delit_changed(_value: float) -> void:
	var blade := _preview.current_blade()
	if blade == null:
		return
	var visuals := blade.get_node_visuals()
	var forced := int(_delit_spin.value)
	for i in visuals.size():
		visuals[i].disabled = i >= visuals.size() - forced and forced > 0


## Keeps the quarry standing through a spam session: refill anything that took a
## hit, so the same swing can be fired again against the same board. Off = the
## real cascade runs and the world degrades, which is the honest behaviour.
func _on_node_damaged(node: SkillNode, _amount: float, _source: Variant) -> void:
	if not is_instance_valid(_immortal_toggle) or not _immortal_toggle.button_pressed:
		return
	if node.owned_by == _quarry:
		node.refill.call_deferred(true)


# ── Style knobs ──────────────────────────────────────────────────────────────

func _build_knobs() -> void:
	for child in _knob_box.get_children():
		child.queue_free()
	for spec in _KNOBS:
		_knob_box.add_child(_make_knob(spec))


func _make_knob(spec: Array) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = spec[1]
	label.custom_minimum_size = Vector2(150.0, 0.0)
	label.add_theme_font_size_override(&"font_size", 11)
	var slider := HSlider.new()
	slider.min_value = spec[2]
	slider.max_value = spec[3]
	slider.step = spec[4]
	slider.value = _style.get(spec[0])
	slider.custom_minimum_size = Vector2(150.0, 0.0)
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	var value := Label.new()
	value.custom_minimum_size = Vector2(46.0, 0.0)
	value.add_theme_font_size_override(&"font_size", 11)
	value.text = "%.2f" % float(slider.value)
	slider.value_changed.connect(func(v: float) -> void:
		_style.set(spec[0], v)
		value.text = "%.2f" % v)
	row.add_child(label)
	row.add_child(slider)
	row.add_child(value)
	return row


## Swap the live style — from the Inspector, or from the working copy. The blade
## re-reads it through `changed`, so a swing in flight repaints too.
func set_style(style: BladeStyle) -> void:
	if style == null:
		return
	_style = style
	var blade := _preview.current_blade()
	if blade != null:
		blade.style = _style
	_build_knobs()


# ── Focus gating ─────────────────────────────────────────────────────────────

## The whole point of the switch the owner asked for: an unfocused tab must not
## crunch a movement sim. Hidden → the preview loop stops, the world subtree stops
## processing, and the viewport stops redrawing. Shown → all three come back.
##
## The viewport is toggled, never remounted: re-adding it is what kills the glow
## pass (`docs/domain/hdr-color.md`, failure mode 5).
func _on_visibility_changed() -> void:
	var live := is_visible_in_tree()
	_world.render_target_update_mode = SubViewport.UPDATE_ALWAYS if live \
			else SubViewport.UPDATE_DISABLED
	_world.process_mode = Node.PROCESS_MODE_INHERIT if live else Node.PROCESS_MODE_DISABLED
	if _preview != null:
		_preview.preview_enabled = live and _preview_toggle.button_pressed


# ── Status / re-arm ──────────────────────────────────────────────────────────

## A swing ended when the plan goes null (BattleSystem clears it post-launch).
## Refill AP, put a fresh melee plan up and — if asked — replay the exact same
## pivot + members through the real click channel, so Launch is live again with
## zero clicks in between.
func _on_plan_changed(plan: AttackPlan) -> void:
	if plan is MeleeAttackPlan:
		var melee := plan as MeleeAttackPlan
		if melee.source != null:
			_last_selection = [melee.source]
			_last_selection.append_array(melee.blade_nodes)
		_refresh_status()
		return
	if plan != null or not is_inside_tree():
		return
	_reset_board(_wielder)
	_battle.request_attack_mode(BattleSystem.AttackMode.MELEE)
	if _rearm_toggle.button_pressed:
		for n in _last_selection:
			if is_instance_valid(n) and n.owned_by == _wielder:
				_input.route_left_click(n)
	_refresh_status()


func _refresh_status() -> void:
	var plan := _battle.attack_plan as MeleeAttackPlan
	var picked := 0 if plan == null or plan.source == null else 1 + plan.blade_nodes.size()
	var ap: PoolStat = _wielder.stat_board.action_points if _wielder.stat_board != null else null
	_status.text = "blade %d/%d · AP %d · %s" % [
		picked,
		1 + (plan.max_blades() if plan != null else 0),
		int(ap.current) if ap != null else 0,
		"preview on" if _preview.preview_enabled else "preview off",
	]
