@tool
class_name HoverPreview
extends Node

## Peek-ahead: hovering a menu node reveals its children, faint and small, at
## the collapsed slots they already rest in (#567 / #571).
##
## [b]This unit reveals; it does not place.[/b] #570 already parks every
## non-focus-path view on its parent at
## [constant FrontmatterLayout.PREVIEW_SCALE] — the collapsed slot is where those
## children LIVE, not somewhere a hover puts them, which is exactly what #571
## means by [i]"the preview position is canonical, not a hover trick"[/i] and is
## what keeps the peek-ahead and #570's sprout in lockstep instead of being two
## implementations of one set of coordinates. Nothing here writes a position, a
## scale or a parent: under #567's constraint 1 ([i]"no detaching, ever"[/i])
## a hover must not be able to move a node, and the only way to guarantee that
## is to own no code that could.
##
## So the whole unit is one pure function over the tree — [method plan], which
## says how visible every node is right now — plus the application of it to the
## [CanvasItem]s a caller hands over. The motion notes frame the peek-ahead as a
## fog-of-war reveal rather than a tooltip, and a reveal IS an alpha ramp.
##
## [b]Alpha, deliberately, and not [code]visible[/code].[/b] Toggling `visible`
## has no half-way state, so it cannot ride #570's `set_progress(t)` clock; and
## `docs/domain/hdr-color.md`'s house rule is that alpha is the fade channel
## while colour value is the dimmer, which is what a fade-in wants.
##
## [b]It owns no [Tween].[/b] [method set_progress] takes `t` in 0..1 and one
## external caller drives it, per the repo's animated-unit convention
## (`ui/tooltip_fan/addon_item.gd`); [method apply] defaults to landing at once
## so a caller that never drives a clock still gets a correct picture.

## Emitted when [method apply] changes which node is being peeked at. #576's
## input map and #578's live tab hang off this rather than polling.
signal hover_changed(id: StringName)

## How visible a peeked-at child is. Small, dim and non-interactive — enough to
## read the shape of what is behind a node, not enough to be mistaken for
## something you can click.
@export_range(0.0, 1.0, 0.01) var preview_alpha: float = 0.45

## How visible a collapsed node is when nothing is peeking at it. Zero: the
## reveal is a reveal. Exposed rather than hardcoded because #578's live tab
## tunes exactly this kind of number, and because a debugging session wants to
## be able to see the whole tree at once.
@export_range(0.0, 1.0, 0.01) var hidden_alpha: float = 0.0

## Full visibility — the focus path and the option column, which are simply the
## menu and are never dimmed by this unit.
const FULL_ALPHA := 1.0

## What [method plan]'s static form uses when a caller states no numbers of its
## own — the same values the exports above default to, so the pure function and
## a freshly instanced unit agree.
const DEFAULT_PREVIEW_ALPHA := 0.45
const DEFAULT_HIDDEN_ALPHA := 0.0

var tree: MenuGraph = null

## The node the camera is centred on, as #570 reports it. Not written here.
var focus_id: StringName = &""
## The node being peeked at, `&""` for none.
var hovered_id: StringName = &""

var _node_lookup: Callable = Callable()
var _edge_lookup: Callable = Callable()
## id -> alpha at the start of the current fade, and id -> alpha it is heading
## for. Same from/to idiom [FrontmatterRoot] uses for poses, for the same
## reason: [method set_progress] is then a straight interpolation and a test can
## assert `t == 0` and `t == 1` without chasing frames.
var _from: Dictionary = {}
var _to: Dictionary = {}
## id -> `[[control, mouse_filter, focus_mode], ...]`, captured once at
## [method bind] so "restore the prior state exactly" restores what the SCENE
## authored rather than whatever a previous preview happened to leave behind.
var _picking: Dictionary = {}


## Hands this unit the tree and two lookups: `node_lookup(id) -> CanvasItem` for
## a menu node's view and `edge_lookup(child_id) -> CanvasItem` for the edge
## arriving at it (a tree, so one incoming edge per node — the same keying
## [method FrontmatterRoot._build_edges] uses).
##
## [b]Callables rather than a [FrontmatterRoot] reference[/b], so this unit
## neither knows nor can reach the navigation state it must not touch, and so a
## test can drive it over bare [CanvasItem]s.
func bind(menu_tree: MenuGraph, node_lookup: Callable, edge_lookup: Callable) -> void:
	tree = menu_tree
	_node_lookup = node_lookup
	_edge_lookup = edge_lookup
	_from = {}
	_to = {}
	_capture_picking()


## Re-states where the menu is and what is being peeked at, and starts the fade
## between the old picture and the new one.
##
## [param instant] (the default) lands it in one frame. A caller that wants the
## reveal to ramp passes `false` and then drives [method set_progress] — that
## caller owns the clock, this unit owns no [Tween].
func apply(focus: StringName, hovered: StringName, instant: bool = true) -> void:
	var changed := hovered != hovered_id
	focus_id = focus
	hovered_id = hovered
	_from = _current_alphas()
	_to = plan(tree, focus_id, hovered_id, preview_alpha, hidden_alpha)
	_apply_picking()
	if instant:
		set_progress(1.0)
	else:
		set_progress(0.0)
	if changed:
		hover_changed.emit(hovered_id)


## Applies the reveal at clock position `t` (0..1) — every node view and every
## edge lerped from the alpha it had when [method apply] was called to the alpha
## [method plan] wants for it.
func set_progress(t: float) -> void:
	var eased := clampf(t, 0.0, 1.0)
	for id: StringName in _to:
		var alpha: float = lerpf(_from.get(id, FULL_ALPHA), _to[id], eased)
		_set_alpha(_node(id), alpha)
		_set_alpha(_edge(id), alpha)


## How visible every node in [param tree] is, given where the menu is focused
## and what is being peeked at. The unit's whole decision, as one pure function.
##
## Three bands, and the ordering between them is the design:
##
## 1. [b]Whatever is at its canonical home is never dimmed.[/b] The test is
##    [i]"is this node's parent on the focus path"[/i] — deliberately the SAME
##    condition [method FrontmatterRoot._target_pose] uses to decide home versus
##    collapsed, so "full" here means exactly "grown out" there and the two
##    cannot drift into disagreeing about which nodes are part of the menu you
##    are currently looking at. It covers the focus path itself, the option
##    column, and the siblings you left behind at every shallower level.
## 2. [b]The peeked-at node's children[/b] come up to [param preview]. A
##    terminal node has none, which is the whole of "hovering a leaf previews
##    nothing" — no branch, just an empty child list (#575's stat-block tooltip
##    is what a leaf gets instead, and the two are mutually exclusive by
##    construction rather than by a rule either of them enforces). Hovering a
##    node that is already home is likewise a no-op: its children are home too,
##    and band 1 wins.
## 3. [b]Everything else is collapsed and unrevealed[/b], at [param hidden].
##
## An edge is keyed by the node it arrives at and takes that node's alpha, so a
## revealed child arrives with its own faint edge and no edge ever outlives the
## node on its far end.
static func plan(
	tree_: MenuGraph,
	focus: StringName,
	hovered: StringName,
	preview: float = DEFAULT_PREVIEW_ALPHA,
	hidden: float = DEFAULT_HIDDEN_ALPHA
) -> Dictionary:
	var alphas: Dictionary = {}
	if tree_ == null:
		return alphas
	var path := tree_.path_to(focus)
	var peeked := previewed(tree_, hovered)
	for id in tree_.ids():
		var parent := tree_.parent_of(id)
		if parent == &"" or path.has(parent):
			alphas[id] = FULL_ALPHA
		elif peeked.has(id):
			alphas[id] = preview
		else:
			alphas[id] = hidden
	return alphas


static func previewed(tree_: MenuGraph, hovered: StringName) -> Array[StringName]:
	var none: Array[StringName] = []
	if tree_ == null or hovered == &"" or not tree_.has(hovered):
		return none
	return tree_.children_of(hovered)


## Where the currently peeked-at children sit, straight off the solver — the
## same slots #570's sprout grows them out of.
##
## Exposed so a test (and #578's live tab) can state the lockstep as an equality
## rather than as a comment. Nothing in this unit writes these positions.
func preview_positions() -> Dictionary:
	return FrontmatterLayout.preview_slots(tree, hovered_id)


## Whether a node at [param alpha] may be clicked. Only a fully visible one:
## a preview is a look-ahead, and #571 requires it to neither accept mouse input
## nor take focus.
static func is_interactive(alpha: float) -> bool:
	return is_equal_approx(alpha, FULL_ALPHA)


func _node(id: StringName) -> CanvasItem:
	if not _node_lookup.is_valid():
		return null
	return _node_lookup.call(id) as CanvasItem


func _edge(child_id: StringName) -> CanvasItem:
	if not _edge_lookup.is_valid():
		return null
	return _edge_lookup.call(child_id) as CanvasItem


func _set_alpha(item: CanvasItem, alpha: float) -> void:
	if item == null:
		return
	var m := item.modulate
	m.a = alpha
	item.modulate = m


func _current_alphas() -> Dictionary:
	var now: Dictionary = {}
	if tree == null:
		return now
	for id in tree.ids():
		var view := _node(id)
		now[id] = view.modulate.a if view != null else FULL_ALPHA
	return now


## Records what every menu node's [Control] descendants were authored to do
## about the mouse, so [method _apply_picking] can put them back exactly.
func _capture_picking() -> void:
	_picking = {}
	if tree == null:
		return
	for id in tree.ids():
		var view := _node(id)
		if view == null:
			continue
		var controls: Array = []
		for control in _controls_under(view):
			controls.append([control, control.mouse_filter, control.focus_mode])
		_picking[id] = controls


## Non-interactive means non-interactive: a previewed node's controls neither
## take the mouse nor accept focus. Everything else is restored to the value the
## scene authored, never to a value this unit invented.
func _apply_picking() -> void:
	for id: StringName in _to:
		var interactive := is_interactive(_to[id])
		for entry: Array in _picking.get(id, []):
			var control: Control = entry[0]
			if not is_instance_valid(control):
				continue
			control.mouse_filter = (
				entry[1] as Control.MouseFilter if interactive else Control.MOUSE_FILTER_IGNORE
			)
			control.focus_mode = (
				entry[2] as Control.FocusMode if interactive else Control.FOCUS_NONE
			)


static func _controls_under(node: Node) -> Array[Control]:
	var found: Array[Control] = []
	if node is Control:
		found.append(node as Control)
	for child in node.get_children():
		found.append_array(_controls_under(child))
	return found
