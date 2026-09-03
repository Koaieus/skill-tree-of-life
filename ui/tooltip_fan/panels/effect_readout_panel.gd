@tool
class_name EffectReadoutPanel
extends FanPanel

## Tooltip V2 (#621) — the aura|effect readout: every currently-affecting
## aura/effect on the hovered node, one row per (effect, leaf modifier) pair
## from [method NodeEffectReadout.gather]. Rendered through [SlabRow] — #588's
## generic "tinted text" vocabulary, reused rather than inventing a new row
## component (the issue's own decision).
##
## [b]HIDING RULE (settled).[/b] A row hides when its EFFECTIVE value
## ([method StatModifier.get_effective_value] — never the raw `.value`; a
## formula-bearing modifier's coefficient is not what the node is actually
## getting) DISPLAYS as its operation's neutral element: 0 for
## ADD_BASE/ADD_BONUS/INCREASE, 1 for MULTIPLY. `SET` never hides — it has no
## neutral, per [method StatModifier.format]'s own pipeline doc. "Displays as"
## goes through [method StatDef.format_number] (#622, this issue's own
## dependency) — the SAME rounding the row itself would render with, so a
## value reading "+0" on screen hides even when its raw float is 0.004, and a
## value that reads real never hides just because it's a hair off its literal
## neutral. A `×0` MULTIPLY is annihilation, not the neutral (`×1` is) — it
## is never a hide candidate.
##
## [b]ROLLUP (owner comment, 2026-08-27).[/b] Individually-hidden rows are
## grouped by `(stat_id, operation)`. If the GROUP's own combined contribution
## — summed for ADD_BASE/ADD_BONUS/INCREASE, multiplied for MULTIPLY, the same
## composition each op uses in the live pipeline (see [method StatModifier]'s
## own pipeline doc) — displays as non-neutral, ONE rolled-up row replaces the
## whole group instead of it vanishing silently (ten `+0`s that sum to a real
## `+4`). A single hidden row is its own "group of one": its combined value
## equals its own already-neutral value, so it degrades back to a true hide,
## matching the issue's ten-row example rather than a one-row false positive.
##
## [b]"Does this affect me" (in scope, mechanism only — no acceptance test
## pins the visual).[/b] Per [method SkillNode.ownership_bit] — never
## `owned_by == entity` — a row whose [member NodeEffectReadout.source_entity]
## reads HOSTILE relative to the hovered node tints redder, so an intruding
## enemy aura reads differently from the territory's own. Kept minimal
## (retint an existing [SlabRow], no new chrome) since #621 leaves the exact
## rendering open.
##
## [b]CAP + CAROUSEL (owner call, 2026-08-31).[/b] A node can legitimately sit
## under more auras than the panel's authored envelope fits, and the usual
## answer — a ScrollContainer — is unusable HERE BY CONSTRUCTION: the pointer is
## captive on the node this tooltip describes, so it can never reach the panel
## to scroll it. So the panel caps at [member max_rows_per_page] rows and PAGES
## instead: fill, hold, crossfade, next page, loop. Pagination is by whole rows,
## never by pixels, which is what makes "no row is ever rendered clipped"
## structural rather than a tuning result — a row is either wholly on this page
## or wholly on the next. Pages are balanced ([method paginate]) so the last one
## is never a lonely leftover.
##
## Under the cap there is NO carousel and no page indicator — one page, no
## tween, no subheader rewrite: the panel behaves exactly as it did before the
## cap existed. The indicator rides the authored [PanelHeader] subheader rather
## than a new node, because adding a child under an instanced sub-scene is the
## `[editable path=]` trap (`.claude/rules/scene-composition.md`), too much
## scene surgery for three characters of chrome.

const _SLAB_ROW_SCENE: PackedScene = preload("res://ui/tooltip_fan/slab_row.tscn")

const _ROW_STAGGER_STEP := 0.12
const _ROW_STAGGER_CAP := 0.85

## The cap, expressed in ROWS. Rows here are uniform single-line [SlabRow]s
## ([method SlabRow._get_minimum_size] is one line plus fixed insets), so a row
## count IS a height — and a count is the only form of the cap that can be
## reasoned about without a layout pass.
##
## [b]Coupled to the authored envelope[/b] (the skin's `custom_minimum_size` in
## `effect_readout_panel.tscn`): the default 4 fits inside it alongside the
## header, and that is what makes "the panel stops growing" true. Raising this
## without raising that envelope re-introduces exactly the unbounded growth the
## cap exists to stop — `test_effect_readout_panel.gd` pins the pair.
@export_range(1, 12, 1) var max_rows_per_page: int = 4

@export_group("Carousel")
## How long a filled page holds before it crossfades to the next — the owner's
## number, long enough to read a full page without hurrying.
@export var page_hold_duration := 2.5
## One leg of the crossfade (out, then in); a page swap costs twice this.
@export var page_fade_duration := 0.25

## Rollup rows read as an aggregate, not an ordinary boon — same reasoning as
## GrantedModifiersRoot's muted empty-state tone, one tier brighter since this
## one is still a real (if summarized) number.
const _ROLLUP_TINT := Color(0.6, 0.62, 0.68)

## How far a HOSTILE-sourced row's tint shifts toward red (#621's "does this
## affect me"). 0 would be inert; kept modest so the row still reads as its
## stat's own colour first.
const _HOSTILE_MIX := 0.35
const _HOSTILE_TINT := Color(0.9, 0.25, 0.25)

var _bound_node: SkillNode = null
var _bound_graph: Graph = null
var _row_setters: Array[Callable] = []
var _has_rows := false

## The `{text, tint}` row dictionaries [method _build_row] returns, split into
## pages. A size of 1 or 0 means the carousel is off.
var _pages: Array[Array] = []
var _page_index := 0
var _carousel: Tween = null
## The subheader the scene authored — the page indicator borrows that slot
## while paging and has to give it back.
var _authored_subheader := ""


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	# The scene authors both halves of the header ("EFFECTS" / "What's
	# touching this node"); re-binding here would silently drop the
	# subheader. Cache it instead — the page indicator borrows that slot.
	_authored_subheader = _header.subheader


## Public entry point (#621).
func bind(node: SkillNode, graph: Graph) -> void:
	_bound_node = node
	_bound_graph = graph
	_rebuild_rows()


## False when nothing currently affects the node — no empty box, matching
## every other crown panel's [method FanPanel.has_content] contract (unlike
## [GrantedModifiersRoot], which is deliberately exempt).
func has_content() -> bool:
	return _has_rows


func _rebuild_rows() -> void:
	if _rows == null:
		return
	_kill_carousel()
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_row_setters.clear()
	_has_rows = false
	if _bound_node == null or _bound_graph == null:
		return

	var shown: Array[Dictionary] = []
	var hidden_by_group: Dictionary = {}  # "<stat_id>|<op>" -> Array[NodeEffectReadout]

	for entry in NodeEffectReadout.gather(_bound_node, _bound_graph):
		var m := entry.modifier
		var def: StatDef = StatRegistry.get_def(m.stat_id)
		if def == null:
			continue  # no def, nothing honest to render (name, tint, type)
		var effective := m.get_effective_value(_bound_node.node_board)
		if m.operation != StatModifier.Operation.SET \
				and _displays_as_neutral(m.operation, effective, def.value_type):
			var key := _group_key(m.stat_id, m.operation)
			if not hidden_by_group.has(key):
				hidden_by_group[key] = []
			(hidden_by_group[key] as Array).append(entry)
			continue
		shown.append(_build_row(entry, def))

	for key in hidden_by_group:
		var group: Array = hidden_by_group[key]
		var first: NodeEffectReadout = group[0]
		var stat_id: StringName = first.modifier.stat_id
		var op: StatModifier.Operation = first.modifier.operation
		var def: StatDef = StatRegistry.get_def(stat_id)
		var combined := _combine(op, group)
		if _displays_as_neutral(op, combined, def.value_type):
			continue  # negligible in aggregate too — hide for real
		shown.append(_build_rollup_row(stat_id, op, combined, group.size(), def))

	_has_rows = not shown.is_empty()
	_pages = paginate(shown, max_rows_per_page)
	_page_index = 0
	_render_current_page()
	_refresh_carousel()



# --- cap + carousel (#621 acceptance 9-11) ------------------------------------

## Splits [param rows] into at most [param per_page] rows each, BALANCED: the
## page count is `ceil(n / per_page)` and the rows are then spread as evenly as
## that many pages allow, so eleven rows at a cap of four read 4/4/3 rather than
## 4/4/4/... and a trailing page of one. Order is preserved end to end — page
## `i` holds a contiguous run — so "wait long enough and you have seen every
## row, in order" is a property of this function alone.
##
## Static and pure: this is the whole of the carousel that can be wrong in a way
## a headless test can catch, so it is kept reachable without a panel.
static func paginate(rows: Array, per_page: int) -> Array[Array]:
	var out: Array[Array] = []
	if rows.is_empty():
		return out
	var cap: int = maxi(per_page, 1)
	if rows.size() <= cap:
		out.append(rows.duplicate())
		return out
	var page_count: int = ceili(float(rows.size()) / float(cap))
	var taken := 0
	for i in page_count:
		# Ceiling-divide the REMAINDER by the pages left: front-loads the odd
		# rows, never exceeds `cap` (which is what the page count was derived
		# from), and cannot leave a page empty.
		var remaining: int = rows.size() - taken
		var pages_left: int = page_count - i
		var take: int = ceili(float(remaining) / float(pages_left))
		out.append(rows.slice(taken, taken + take))
		taken += take
	return out


## Whether the carousel is running for the current content — false under the
## cap, which is acceptance 10's "behaves exactly as PanelLayout does today".
func is_paging() -> bool:
	return _pages.size() > 1


## Tears down the current rows and rebuilds them from [member _page_index].
## Every page swap goes through here, so a row's reveal state is re-derived
## from the panel's live [member FanPanel.progress] rather than inherited from
## whatever the previous page's rows happened to be sitting at.
func _render_current_page() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_row_setters.clear()
	if _pages.is_empty():
		return
	for row_data in _pages[_page_index]:
		var row := _SLAB_ROW_SCENE.instantiate() as SlabRow
		_rows.add_child(row)
		row.bind_text(row_data["text"], row_data["tint"])
		_row_setters.append(row.set_progress)
	_apply_row_stagger()


## Advances to the next page, wrapping. Public so the cycle is assertable
## without waiting out a 2.5s hold in a test.
func advance_page() -> void:
	if not is_paging():
		return
	_page_index = (_page_index + 1) % _pages.size()
	_render_current_page()
	_refresh_page_indicator()


## Starts the hold → fade-out → swap → fade-in loop, or leaves everything
## inert (and restores the authored subheader) when the content fits.
func _refresh_carousel() -> void:
	_kill_carousel()
	_refresh_page_indicator()
	if not is_paging():
		return
	_carousel = create_tween().set_loops()
	_carousel.tween_interval(page_hold_duration)
	_carousel.tween_property(_rows, "modulate:a", 0.0, page_fade_duration)
	_carousel.tween_callback(advance_page)
	_carousel.tween_property(_rows, "modulate:a", 1.0, page_fade_duration)


## Kills the loop and snaps the row column back to fully opaque — the same
## "never leave it parked mid-animation" rule [method FanPanel._kill_idle]
## follows for the idle float.
func _kill_carousel() -> void:
	if _carousel != null and _carousel.is_valid():
		_carousel.kill()
	_carousel = null
	if _rows != null:
		var m := _rows.modulate
		m.a = 1.0
		_rows.modulate = m


func _refresh_page_indicator() -> void:
	if _header == null:
		return
	_header.subheader = "%d / %d" % [_page_index + 1, _pages.size()] if is_paging() \
		else _authored_subheader


## The carousel is a SETTLED-state loop, like the idle float: a panel on its
## way out must not swap pages under the fade.
func play_out() -> Tween:
	_kill_carousel()
	return super.play_out()


func _group_key(stat_id: StringName, op: StatModifier.Operation) -> String:
	return "%s|%d" % [stat_id, op]


## Whether [param v] renders identically to the operation's neutral element
## through the stat's OWN declared type — the shared #622 rounding, so a value
## that reads "+0"/"×1" on screen hides even when its raw float is a hair off.
func _displays_as_neutral(op: StatModifier.Operation, v: float, value_type: StatDef.ValueType) -> bool:
	var neutral := 1.0 if op == StatModifier.Operation.MULTIPLY else 0.0
	return StatDef.format_number(value_type, v) == StatDef.format_number(value_type, neutral)


## The group's own combined contribution, composed the same way the live
## pipeline composes that operation (`Σ ADD_BASE`/`Σ INCREASE`/`Π MULTIPLY` —
## see [method StatModifier]'s class doc) — never a plain sum for MULTIPLY,
## which would answer a different question.
func _combine(op: StatModifier.Operation, group: Array) -> float:
	if op == StatModifier.Operation.MULTIPLY:
		var product := 1.0
		for entry in group:
			product *= (entry as NodeEffectReadout).modifier.get_effective_value(_bound_node.node_board)
		return product
	var total := 0.0
	for entry in group:
		total += (entry as NodeEffectReadout).modifier.get_effective_value(_bound_node.node_board)
	return total


func _build_row(entry: NodeEffectReadout, def: StatDef) -> Dictionary:
	var effect_name := "Effect"
	if entry.effect != null and not entry.effect.display_name.is_empty():
		effect_name = entry.effect.display_name
	var text := "%s: %s" % [effect_name, entry.modifier.format_effective(_bound_node.node_board)]
	return {"text": text, "tint": _row_tint(def.tint_color, _is_hostile(entry.source_entity))}


func _build_rollup_row(stat_id: StringName, op: StatModifier.Operation, combined: float, count: int, def: StatDef) -> Dictionary:
	# A bare (formula-less) synthetic modifier reuses format_effective()'s
	# grammar for free instead of re-deriving the op-text switch a third time
	# (StatModifier._format_value already has it; contribution_text() is the
	# other one) — get_effective_value(null) on a formula-less modifier is
	# just `value`, so `combined` renders exactly.
	var synthetic := StatModifier.new()
	synthetic.stat_id = stat_id
	synthetic.operation = op
	synthetic.value = combined
	var text := "%d minor sources: %s" % [count, synthetic.format_effective()]
	return {"text": text, "tint": _ROLLUP_TINT}


## #621's "does this affect me": HOSTILE per [method SkillNode.ownership_bit],
## relative to the hovered node — never `owned_by == entity`. Answers "is this
## effect's source at odds with whoever holds this territory", which stays
## meaningful even when the hovering player owns neither side (a
## third-party's node caught between two auras).
func _is_hostile(source_entity: Entity) -> bool:
	if _bound_node == null or source_entity == null:
		return false
	return (_bound_node.ownership_bit(source_entity) & SkillNode.Ownership.HOSTILE) != 0


func _row_tint(base: Color, hostile: bool) -> Color:
	return base.lerp(_HOSTILE_TINT, _HOSTILE_MIX) if hostile else base


func _apply_progress() -> void:
	super._apply_progress()
	_apply_row_stagger()


func _apply_row_stagger() -> void:
	for i in _row_setters.size():
		var delay := clampf(i * _ROW_STAGGER_STEP, 0.0, _ROW_STAGGER_CAP)
		var span := 1.0 - delay
		var row_t := clampf((progress - delay) / span, 0.0, 1.0) if span > 0.0 else progress
		_row_setters[i].call(row_t)
