@tool
class_name CapacityBlips
extends GridContainer
## N-of-max pip display — resolves #87 slice 2 ("empty mana crystal"
## blips). Used for blade-size pips and the Magic spell bar's degree
## icon. Instances CapacityPip children (leaf-level programmatic
## composition per scene-composition.md — the count is data-driven, not
## a fixed structural tree, so this is the sanctioned case-by-case use of
## code composition rather than a hand-authored fixed scene).

const PIP_SCENE := preload("res://ui/gauges/capacity_pip.tscn")

@export var max_count: int = 3:
	set(v):
		var nv: int = max(0, v)
		if max_count == nv:
			return
		max_count = nv
		_rebuild()

@export var count: int = 0:
	set(v):
		count = clamp(v, 0, max_count)
		_apply_state()

@export var fill_color: Color = Color(0.62, 0.21, 0.21, 1.0):
	set(v):
		fill_color = v
		_apply_state()

@export var empty_color: Color = Color(1.0, 1.0, 1.0, 0.08):
	set(v):
		empty_color = v
		_apply_state()

@export var pip_size: Vector2 = Vector2(13, 13):
	set(v):
		pip_size = v
		for pip in get_children():
			if pip is CapacityPip:
				pip.custom_minimum_size = pip_size

## Opt-in run collapsing (#718 tray-width fix). `0` (the default every other
## consumer keeps) is OFF and renders exactly one child per pip, byte for byte
## as before. Above zero, a run of MORE than this many CONSECUTIVE pips sharing
## an identical render signature — fill colour, filled/empty, both outline
## colours, the manual marker and the highlight — renders as ONE pip plus a
## `× N` label instead of N pips.
##
## **Owner call 2026-09-04:** *"collapse, loses interactivity -> fine, for that
## amount its unwieldy to be clicking pips"* — a collapsed chip is deliberately
## click-dead (the graph node itself is still clickable); it only HOVERS, and it
## hovers every node in the run at once.
##
## Why this exists at all: a `Control`'s rect is clamped up to
## `get_combined_minimum_size()`, so a 45-node blade laid out as 45 pips gave
## the Command Tray an unbounded minimum width and pushed it under the End Turn
## button. Collapsing is the content-side half of that fix; [member columns] is
## the structural half (it wraps the pathological non-collapsible case).
@export var collapse_threshold: int = 0:
	set(v):
		var nv: int = max(0, v)
		if collapse_threshold == nv:
			return
		collapse_threshold = nv
		_rebuild()

## Indices (0-based) currently selection-highlighted, e.g. blade nodes
## picked in the Melee builder. Cleared/rebuilt on every count() change.
var highlighted_indices: Array[int] = []:
	set(v):
		highlighted_indices = v
		_apply_state()

## Per-filled-pip color override (#406) — index i colors the i'th filled pip
## (0..count-1); shorter than `count` falls back to `fill_color` for the
## remainder. Empty (the default) keeps the single-color behavior. Lets one
## blip row mix budget "kinds" sharing the same pool (e.g. blade-member
## spend vs. a temp Spike vs. a temp Clamp) while still reading as one
## N-of-max gauge.
var segment_colors: Array[Color] = []:
	set(v):
		segment_colors = v
		_apply_state()

## Melee blade blips (#406 follow-up): pips as click/hover UI elements instead
## of a pure readout. Off by default — every other CapacityBlips consumer
## (CombatCardMelee's size gauge, the Magic spell-bar degree icon) stays a
## non-interactive `MOUSE_FILTER_IGNORE` readout.
@export var interactive: bool = false:
	set(v):
		interactive = v
		_rebuild()

## Parallel to segment_colors — the SkillNode index i's pip represents, or
## null for a pip with no real node behind it (unspent blade capacity). Only
## consulted when `interactive`.
var bound_nodes: Array = []:
	set(v):
		bound_nodes = v
		_apply_state()

## Addon-outline colors per filled pip, parallel to segment_colors. A default
## (fully transparent) Color at index i means "no outline of that kind" —
## see capacity_pip.gdshader.
var outline_colors_a: Array[Color] = []:
	set(v):
		outline_colors_a = v
		_apply_state()

var outline_colors_b: Array[Color] = []:
	set(v):
		outline_colors_b = v
		_apply_state()

## True at index i marks a player-applied (temp) upgrade on that pip's node,
## as opposed to one that shipped from procgen — see CapacityPip.manual_marker.
var manual_markers: Array[bool] = []:
	set(v):
		manual_markers = v
		_apply_state()

## Emitted on a left-click of an interactive pip with a bound node.
signal pip_clicked(node: SkillNode)
## Emitted when the mouse enters/exits an interactive pip with a bound node.
signal pip_hover_changed(node: SkillNode, hovering: bool)

func _ready() -> void:
	_rebuild()


## One maximal group of consecutive pips sharing a render signature. The
## rendering plan is a LIST of these — never an index into six parallel arrays.
##
## That distinction is the whole point: `_apply_state()` used to assume
## `get_children()[i]` lined up 1:1 with `segment_colors[i]`, `bound_nodes[i]`,
## `outline_colors_a[i]`, `outline_colors_b[i]`, `manual_markers[i]` and
## `highlighted_indices`. Collapsing breaks that contract in six places at
## once, so the collapsing path resolves every array ONCE, up front, into runs
## that carry their own style and their own nodes.
class Run extends RefCounted:
	var fill: Color
	var filled: bool
	var outline_a: Color
	var outline_b: Color
	var manual: bool
	var highlighted: bool
	## The raw `bound_nodes` entries this run covers, in order. Deliberately
	## untyped and unvalidated — a typed read of a freed Object crashes at the
	## assignment (`docs/domain/gdscript-pitfalls.md`), so validity is checked
	## at emit time, not here.
	var nodes: Array = []

	func count() -> int:
		return nodes.size()

	func same_style(other: Run) -> bool:
		return fill == other.fill \
				and filled == other.filled \
				and outline_a == other.outline_a \
				and outline_b == other.outline_b \
				and manual == other.manual \
				and highlighted == other.highlighted

	func equals(other: Run) -> bool:
		return same_style(other) and nodes == other.nodes


## The run list currently on screen, so a burst of setter calls (MeleeBody
## pushes six properties per refresh) rebuilds the children at most once.
var _rendered_runs: Array[Run] = []


func _rebuild() -> void:
	_teardown_children()
	_rendered_runs = []
	if collapse_threshold > 0:
		_apply_state()
		return
	for i in max_count:
		var pip: CapacityPip = _make_pip("CapacityPip_%02d" % i)
		if interactive:
			pip.mouse_filter = Control.MOUSE_FILTER_STOP
			pip.gui_input.connect(_on_pip_gui_input.bind(i))
			pip.mouse_entered.connect(_on_pip_hover.bind(i, true))
			pip.mouse_exited.connect(_on_pip_hover.bind(i, false))
		else:
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_state()


func _teardown_children() -> void:
	# remove_child() first, unconditionally: it detaches the child and frees
	# its name slot synchronously, so the same names are safe to reuse below
	# in this same call regardless of when the object itself actually goes
	# away — that's what the old "Children name does not match parent name in
	# hashtable" bug needed, not an immediate free.
	#
	# queue_free() (not free()) for the object itself: a pip click now can
	# reenter _rebuild() synchronously (pip_clicked -> request_temp_upgrade_at
	# -> state_changed -> attack_plan_state_changed -> MeleeBody._refresh()),
	# while that same pip's own gui_input signal is still on the call stack.
	# An immediate free() on an object mid-signal-emission is a locked-object
	# error; queue_free() defers the actual deletion past that emission.
	#
	# #510 narrowed this but did not remove it. The toggle is a Command now, so
	# the MUTATION half can no longer re-enter — `attack_plan_state_changed`
	# fires while CommandApplier holds its guard, and a second toggle raised
	# from this rebuild is refused by `can_player_act()` or queued behind the
	# first (test/unit/systems/test_command_routing.gd pins both). The REBUILD
	# still happens mid-emission, so the queue_free() above is still load-bearing.
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _make_pip(pip_name: String) -> CapacityPip:
	var pip: CapacityPip = PIP_SCENE.instantiate()
	pip.name = pip_name
	pip.custom_minimum_size = pip_size
	add_child(pip)
	# Deliberately NOT stamping pip.owner in the editor: doing so let the
	# editor bake these script-created pips into any consuming scene as
	# persistent "editable children" overrides, which then collided with
	# this same _rebuild() teardown on the next load (mismatched pip
	# count/identity vs. what the script expects). Pips render fine in
	# the editor viewport without an owner — they're just not individually
	# selectable in the Scene dock, which is correct for a script-owned,
	# count-driven leaf composition (see class doc above).
	return pip


func _apply_state() -> void:
	if collapse_threshold > 0:
		_render_runs(_compute_runs())
		return
	var children := get_children()
	for i in children.size():
		var pip: CapacityPip = children[i]
		pip.fill_color = segment_colors[i] if i < segment_colors.size() else fill_color
		pip.empty_color = empty_color
		pip.filled = i < count
		pip.highlighted = i in highlighted_indices
		pip.outline_color_a = outline_colors_a[i] if i < outline_colors_a.size() else Color(0, 0, 0, 0)
		pip.outline_color_b = outline_colors_b[i] if i < outline_colors_b.size() else Color(0, 0, 0, 0)
		pip.manual_marker = manual_markers[i] if i < manual_markers.size() else false


# ── The collapsing path ──────────────────────────────────────────────────────


## Resolve the six parallel arrays into maximal same-signature runs, once.
func _compute_runs() -> Array[Run]:
	var runs: Array[Run] = []
	var current: Run = null
	for i in max_count:
		var r := Run.new()
		r.fill = segment_colors[i] if i < segment_colors.size() else fill_color
		r.filled = i < count
		r.outline_a = outline_colors_a[i] if i < outline_colors_a.size() else Color(0, 0, 0, 0)
		r.outline_b = outline_colors_b[i] if i < outline_colors_b.size() else Color(0, 0, 0, 0)
		r.manual = manual_markers[i] if i < manual_markers.size() else false
		r.highlighted = i in highlighted_indices
		var node: Variant = bound_nodes[i] if i < bound_nodes.size() else null
		if current != null and current.same_style(r):
			current.nodes.append(node)
		else:
			r.nodes = [node]
			runs.append(r)
			current = r
	return runs


func _render_runs(runs: Array[Run]) -> void:
	if _runs_equal(runs, _rendered_runs):
		return
	_teardown_children()
	_rendered_runs = runs
	var idx := 0
	for run in runs:
		if run.count() > collapse_threshold:
			var chip := _make_pip("CapacityPip_%02d" % idx)
			idx += 1
			_style_pip(chip, run)
			# Click-dead by owner call — only the hover survives, and it forces
			# hover on EVERY node the chip stands for.
			if interactive:
				chip.mouse_filter = Control.MOUSE_FILTER_STOP
				chip.mouse_entered.connect(_on_run_hover.bind(run.nodes, true))
				chip.mouse_exited.connect(_on_run_hover.bind(run.nodes, false))
			else:
				chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_make_run_label(run.count(), idx))
			idx += 1
		else:
			for node in run.nodes:
				var pip := _make_pip("CapacityPip_%02d" % idx)
				idx += 1
				_style_pip(pip, run)
				if interactive:
					pip.mouse_filter = Control.MOUSE_FILTER_STOP
					pip.gui_input.connect(_on_run_gui_input.bind(node))
					pip.mouse_entered.connect(_on_run_hover.bind([node], true))
					pip.mouse_exited.connect(_on_run_hover.bind([node], false))
				else:
					pip.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _style_pip(pip: CapacityPip, run: Run) -> void:
	pip.fill_color = run.fill
	pip.empty_color = empty_color
	pip.filled = run.filled
	pip.highlighted = run.highlighted
	pip.outline_color_a = run.outline_a
	pip.outline_color_b = run.outline_b
	pip.manual_marker = run.manual


func _make_run_label(n: int, idx: int) -> Label:
	var label := Label.new()
	label.name = "RunCount_%02d" % idx
	label.text = "× %d" % n
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_size_override(&"font_size", 10)
	label.modulate = Color(0.725, 0.765, 0.863, 0.75)
	return label


func _runs_equal(a: Array[Run], b: Array[Run]) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not a[i].equals(b[i]):
			return false
	return true


## Force-hover every node a chip stands for. A single (uncollapsed) pip goes
## through the same door with a one-element array, so MeleeBody only ever needs
## one balancing rule for both.
func _on_run_hover(nodes: Array, hovering: bool) -> void:
	for stored in nodes:
		if is_instance_valid(stored):
			pip_hover_changed.emit(stored as SkillNode, hovering)


func _on_run_gui_input(event: InputEvent, stored: Variant) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		return
	if is_instance_valid(stored):
		pip_clicked.emit(stored as SkillNode)


# ── The flat (collapse_threshold == 0) path, unchanged ───────────────────────


## `bound_nodes[index]` read defensively — per gdscript-pitfalls.md, a typed
## read of a freed Object crashes at the assignment, so this stays untyped
## until the validity check.
func _bound_node_at(index: int) -> SkillNode:
	if index < 0 or index >= bound_nodes.size():
		return null
	var stored = bound_nodes[index]
	return stored if is_instance_valid(stored) else null


func _on_pip_gui_input(event: InputEvent, index: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		return
	var node := _bound_node_at(index)
	if node != null:
		pip_clicked.emit(node)


func _on_pip_hover(index: int, hovering: bool) -> void:
	var node := _bound_node_at(index)
	if node != null:
		pip_hover_changed.emit(node, hovering)
