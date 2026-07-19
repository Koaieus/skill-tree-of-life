@tool
extends Control
## Procgen playground panel (#166) — a live-edit sandbox tab for tuning what
## procgen rolls, without booting a level.
##
## Layout: a left sidebar (preset folder access + the sampling controls shared
## by both sub-tabs) beside a [TabContainer] with "Map Sample" / "Node Graph".
##
## Sidebar:
## - "Open Presets Folder" reveals `res://procgen/presets/` in the editor's
##   FileSystem dock, creating the folder first if this is a fresh checkout.
## - "Sample as:" (archetype) + "Reseed" are shared sampling state — both
##   sub-tabs roll through the same [member _rng] and [method _sample_once],
##   so they belong here once, not duplicated per tab.
##
## Inspector live-sync (#166): [method load_config] (the [SandboxLiveTab]
## loader hook) fires when a [GraphProcgenConfig] becomes the inspected
## object — a fresh duplicate is taken as the working `_config` (never mutate
## the on-disk resource) and `_source_config` remembers the *live* reference.
## [method refresh_from_config] is what the editor plugin calls on every
## `property_edited` (including edits on nested sub-resources like
## `budget_policy` or a [ScalarField] child) — it re-duplicates
## `_source_config` and re-renders both sub-tabs in place: the map keeps its
## clicked marker and re-samples at it, the graph keeps its node positions
## (same seed) and just re-colours/re-samples. Tweaking a field preset in the
## inspector is meant to feel instant, not like re-opening the tab.
##
## Sub-tab "Map Sample": renders a [GraphProcgenConfig]'s budget-field heatmap
## ([FieldMapView]); clicking a spot rolls a batch of independent draws there
## (budget via [BudgetPolicy] + content via the phased v3 draw) and lays them
## out as cards, so a designer gets an at-a-glance feel of what a node in that
## territory tends to roll. Each card also shows the roll's factor breakdown
## (raw draw + whichever multipliers departed from neutral) via
## [method _breakdown_text]. Hovering the map shows the field value + base
## range at that point before you commit to a click.
##
## Sub-tab "Node Graph": generates a small preview graph via [NodeGraphView] —
## positions + edges + archetypes (coloured borders) but no content rolled.
## A node here is a *location* to sample; clicking one runs the same
## [method _sample_once] roll a map click does. Node fill + the translucent
## background layer both show the continuous [BudgetPolicy.budget_field] value.
## Stamp simulation (#166): toggle "Paint Mode", pick an archetype + radius,
## click a node to stamp — nodes inside the region get the stamp's archetype
## colour; "Clear Stamps" restores the original BFS-grow assignments.
##
## Self-contained: defaults to a duplicated `first_level.tres` so it works with
## nothing inspected.

const _DEFAULT_PRESET := preload("res://procgen/presets/first_level/first_level.tres")
const _FieldMapView := preload("res://procgen/playground/field_map_view.gd")
const _NodeGraphView := preload("res://procgen/playground/node_graph_view.gd")
const _PRESETS_DIR := "res://procgen/presets/"

const _SAMPLE_COUNT := 5
## Kept modest — see #172. The SkillNode visual composite registers instance
## shader-uniform slots for 4 RimRings + CoreHalos + RuneRing per node
## regardless of visibility (only ~2 are ever drawn), so stacking this preview
## graph on top of the other always-resident sandbox_host panels can trip a
## software-rasterizer instance-uniform cap well before it would on real GPU
## hardware. 16 measured clean in that combined host; the spinbox still goes
## higher for anyone who wants to push it.
const _GRAPH_PREVIEW_NODE_COUNT := 16

var _config: GraphProcgenConfig
## The live (un-duplicated) resource routed in from the inspector — kept only
## to re-duplicate fresh on every [method refresh_from_config]. Never read for
## anything else; `_config` is the working copy everything else uses.
var _source_config: GraphProcgenConfig
var _rng := RandomNumberGenerator.new()
## Node Graph's own seed, held stable across a live-edit refresh so a
## property tweak re-colours the same layout instead of reshuffling it.
## Reset to a fresh random value on an explicit Regenerate.
var _last_graph_seed := 0

var _bound_label: Label
var _arch_option: OptionButton
var _seed_label: Label

var _map: Control
var _cards_row: HBoxContainer
var _cards: Array[VBoxContainer] = []

var _graph_view: Control
var _graph_node_count_spin: SpinBox
var _graph_cards_row: HBoxContainer
var _graph_cards: Array[VBoxContainer] = []

# Stamp controls (#166)
var _stamp_paint_toggle: Button
var _stamp_arch_option: OptionButton
var _stamp_radius_spin: SpinBox
var _stamp_clear_btn: Button
var _paint_mode := false


func _ready() -> void:
	_build_ui()
	_source_config = _DEFAULT_PRESET
	_set_config(_DEFAULT_PRESET.duplicate(true))


# ── SandboxLiveTab loader hook ────────────────────────────────────────────


## Swap in an inspected config (duplicated so we never mutate the on-disk
## resource). No-op for anything that isn't a GraphProcgenConfig.
func load_config(obj: Object) -> void:
	if obj is GraphProcgenConfig:
		_source_config = obj as GraphProcgenConfig
		_set_config(_source_config.duplicate(true))


## Called by the editor plugin on `property_edited` — `_source_config`'s
## identity hasn't changed but one of its (possibly nested) exports has.
## Re-duplicates and re-renders in place; see the class doc for what "in
## place" preserves (marker, node layout).
func refresh_from_config() -> void:
	if _source_config == null or not is_instance_valid(_source_config):
		return

	var had_marker: bool = _map != null and _map.has_marker()
	var marker_pos: Vector2 = _map.marker_world() if had_marker else Vector2.ZERO
	var preferred_id: StringName = &""
	if _arch_option != null and _arch_option.selected >= 0:
		var meta = _arch_option.get_item_metadata(_arch_option.selected)
		if meta is ArchetypePolicy:
			preferred_id = (meta as ArchetypePolicy).id

	_config = _source_config.duplicate(true)
	GraphProcgen._propagate_mask_radius(_config)
	_populate_archetypes(preferred_id)
	_populate_stamp_archetypes()
	_update_bound_label()

	if _map != null:
		_map.refresh_config(_config)
	if had_marker:
		_on_map_clicked(marker_pos)

	if _graph_view != null and _graph_view.has_nodes():
		_regenerate_graph(true)


# ── UI ────────────────────────────────────────────────────────────────────


func _build_ui() -> void:
	# TODO: "build UI"? but playground_panel.tscn EXISTS? SHAME SHAME SHAME
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override(&"separation", 10)
	add_child(root)

	root.add_child(_build_sidebar())
	root.add_child(VSeparator.new())

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = SIZE_EXPAND_FILL
	tabs.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_child(tabs)

	var map_tab := _build_map_tab()
	tabs.add_child(map_tab)
	tabs.set_tab_title(map_tab.get_index(), "Map Sample")

	var graph_tab := _build_graph_tab()
	tabs.add_child(graph_tab)
	tabs.set_tab_title(graph_tab.get_index(), "Node Graph")


func _build_sidebar() -> VBoxContainer:
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(190, 0)
	sidebar.add_theme_constant_override(&"separation", 6)

	var header := _make_label("Procgen Playground")
	header.add_theme_font_size_override(&"font_size", 13)
	sidebar.add_child(header)

	var open_folder := Button.new()
	open_folder.text = "Open Presets Folder"
	open_folder.tooltip_text = "Reveal res://procgen/presets/ in the FileSystem dock (created first if it doesn't exist yet)."
	open_folder.pressed.connect(_on_open_presets_folder_pressed)
	sidebar.add_child(open_folder)

	_bound_label = _make_label("")
	_bound_label.modulate = Color(1, 1, 1, 0.55)
	_bound_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(_bound_label)

	sidebar.add_child(HSeparator.new())

	sidebar.add_child(_make_label("Sample as:"))
	_arch_option = OptionButton.new()
	sidebar.add_child(_arch_option)

	var reseed := Button.new()
	reseed.text = "Reseed"
	reseed.pressed.connect(_on_reseed_pressed)
	sidebar.add_child(reseed)

	_seed_label = _make_label("")
	_seed_label.modulate = Color(1, 1, 1, 0.55)
	_seed_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(_seed_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	sidebar.add_child(spacer)
	return sidebar


func _build_map_tab() -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.add_theme_constant_override(&"separation", 6)

	# Map.
	_map = _FieldMapView.new()
	_map.size_flags_horizontal = SIZE_EXPAND_FILL
	_map.size_flags_vertical = SIZE_EXPAND_FILL
	_map.connect(&"map_clicked", _on_map_clicked)
	tab.add_child(_map)

	# Sample cards.
	var cards_label := _make_label("%d samples at the clicked spot:" % _SAMPLE_COUNT)
	cards_label.modulate = Color(1, 1, 1, 0.7)
	tab.add_child(cards_label)

	_cards_row = HBoxContainer.new()
	_cards_row.add_theme_constant_override(&"separation", 6)
	_cards_row.custom_minimum_size = Vector2(0, 168)
	tab.add_child(_cards_row)
	for i in _SAMPLE_COUNT:
		var card := _make_card()
		_cards.append(card)
		_cards_row.add_child(card.get_parent())
	_clear_cards(_cards, "Click the map to roll.")
	return tab


func _build_graph_tab() -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.add_theme_constant_override(&"separation", 6)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override(&"separation", 10)
	tab.add_child(bar)

	bar.add_child(_make_label("Preview nodes:"))
	_graph_node_count_spin = SpinBox.new()
	_graph_node_count_spin.min_value = 8
	_graph_node_count_spin.max_value = 80
	_graph_node_count_spin.step = 1
	_graph_node_count_spin.value = _GRAPH_PREVIEW_NODE_COUNT
	bar.add_child(_graph_node_count_spin)

	var regen := Button.new()
	regen.text = "Regenerate graph"
	regen.pressed.connect(_on_regenerate_graph_pressed)
	bar.add_child(regen)

	# Stamp controls — paint a territory onto the preview graph (#166).
	bar.add_child(VSeparator.new())
	bar.add_child(_make_label("Stamp:"))
	_stamp_arch_option = OptionButton.new()
	bar.add_child(_stamp_arch_option)

	bar.add_child(_make_label("r:"))
	_stamp_radius_spin = SpinBox.new()
	_stamp_radius_spin.min_value = 50.0
	_stamp_radius_spin.max_value = 800.0
	_stamp_radius_spin.step = 10.0
	_stamp_radius_spin.value = 200.0
	bar.add_child(_stamp_radius_spin)

	_stamp_paint_toggle = Button.new()
	_stamp_paint_toggle.text = "Paint Mode"
	_stamp_paint_toggle.toggle_mode = true
	_stamp_paint_toggle.tooltip_text = "Toggle on: clicking a node paints a stamp. Toggle off: clicking a node samples its content."
	_stamp_paint_toggle.pressed.connect(_on_paint_mode_toggled)
	bar.add_child(_stamp_paint_toggle)

	_stamp_clear_btn = Button.new()
	_stamp_clear_btn.text = "Clear Stamps"
	_stamp_clear_btn.tooltip_text = "Remove all painted stamps and restore original archetype colours."
	_stamp_clear_btn.pressed.connect(_on_clear_stamps_pressed)
	bar.add_child(_stamp_clear_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	bar.add_child(spacer)

	# Graph.
	_graph_view = _NodeGraphView.new()
	_graph_view.size_flags_horizontal = SIZE_EXPAND_FILL
	_graph_view.size_flags_vertical = SIZE_EXPAND_FILL
	_graph_view.connect(&"node_clicked", _on_graph_node_clicked)
	tab.add_child(_graph_view)

	# Sample cards.
	var cards_label := _make_label("%d samples for the clicked node:" % _SAMPLE_COUNT)
	cards_label.modulate = Color(1, 1, 1, 0.7)
	tab.add_child(cards_label)

	_graph_cards_row = HBoxContainer.new()
	_graph_cards_row.add_theme_constant_override(&"separation", 6)
	_graph_cards_row.custom_minimum_size = Vector2(0, 168)
	tab.add_child(_graph_cards_row)
	for i in _SAMPLE_COUNT:
		var card := _make_card()
		_graph_cards.append(card)
		_graph_cards_row.add_child(card.get_parent())
	_clear_cards(_graph_cards, "Regenerate, then click a node.")
	return tab


## Compact "why this budget" line from a [method BudgetPolicy.compute_budget_breakdown]
## dict — the roll's raw draw + whichever multipliers actually departed from
## neutral (1.0). Neutral factors are omitted so an unmodulated preset doesn't
## clutter every card with "×1.0 ×1.0 ×1.0".
func _breakdown_text(b: Dictionary) -> String:
	var parts: Array[String] = []
	parts.append("raw %.1f of %d–%d" % [float(b.get("raw", 0.0)), int(b.get("base_min", 0)), int(b.get("base_max", 0))])
	var arch_mult := float(b.get("arch_mult", 1.0))
	if not is_equal_approx(arch_mult, 1.0):
		parts.append("arch ×%.2f" % arch_mult)
	var field_scale := float(b.get("field_scale", 1.0))
	if not is_equal_approx(field_scale, 1.0):
		parts.append("field ×%.2f" % field_scale)
	var role_mult := float(b.get("role_mult", 1.0))
	if not is_equal_approx(role_mult, 1.0):
		parts.append("role ×%.2f" % role_mult)
	return "  ·  ".join(parts)


func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


## A card is a VBox inside a PanelContainer; we keep the VBox reference (for
## repopulating rows) and add the PanelContainer to the row.
func _make_card() -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = SIZE_EXPAND_FILL
	frame.size_flags_vertical = SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 2)
	frame.add_child(box)
	return box


## Reveals `_PRESETS_DIR` in the editor's FileSystem dock, creating it first
## if this is a fresh checkout without any authored presets yet.
func _on_open_presets_folder_pressed() -> void:
	if not Engine.is_editor_hint():
		return
	if not DirAccess.dir_exists_absolute(_PRESETS_DIR):
		DirAccess.make_dir_recursive_absolute(_PRESETS_DIR)
		var fs := EditorInterface.get_resource_filesystem()
		if fs != null:
			fs.scan()
	var dock := EditorInterface.get_file_system_dock()
	if dock == null:
		return
	dock.navigate_to_path(_PRESETS_DIR)


# ── Config ────────────────────────────────────────────────────────────────


func _set_config(cfg: GraphProcgenConfig) -> void:
	_config = cfg
	# Resolve any opted-in radial field radius (outer_radius <= 0) from the
	# shape, exactly as GraphProcgen does before sampling.
	if _config != null:
		GraphProcgen._propagate_mask_radius(_config)
	_populate_archetypes()
	_populate_stamp_archetypes()
	_update_bound_label()
	if _map != null:
		_map.set_config(_config)
	_update_seed_label()
	_clear_cards(_cards, "Click the map to roll.")
	_last_graph_seed = 0
	_regenerate_graph()


func _update_bound_label() -> void:
	if _bound_label == null:
		return
	if _source_config == null or not is_instance_valid(_source_config):
		_bound_label.text = "(default preset)"
	elif _source_config.resource_path != "":
		_bound_label.text = "bound: %s" % _source_config.resource_path.get_file()
	else:
		_bound_label.text = "bound: (unsaved config)"


## `preferred_id` re-selects the same archetype after a rebuild (used by
## [method refresh_from_config] so a live-edit doesn't silently reset the
## dropdown); left empty for a genuinely new config, where defaulting to the
## first real archetype is the useful behaviour (see below).
func _populate_archetypes(preferred_id: StringName = &"") -> void:
	if _arch_option == null:
		return
	_arch_option.clear()
	_arch_option.add_item("Any / none")  # id 0 → sample with no archetype
	_arch_option.set_item_metadata(0, null)
	if _config == null:
		return
	var preferred_idx := -1
	for policy in _config.archetypes:
		if policy == null:
			continue
		var idx := _arch_option.item_count
		_arch_option.add_item(String(policy.id))
		_arch_option.set_item_metadata(idx, policy)
		if preferred_id != &"" and policy.id == preferred_id:
			preferred_idx = idx
	if preferred_idx >= 0:
		_arch_option.select(preferred_idx)
	# Default to the first real archetype if there is one — a bare "none" sample
	# only ever draws off-attribute/defensive/rare content, which reads oddly.
	elif _arch_option.item_count > 1:
		_arch_option.select(1)


func _selected_archetype() -> ArchetypePolicy:
	if _arch_option == null or _arch_option.selected < 0:
		return null
	var meta = _arch_option.get_item_metadata(_arch_option.selected)
	return meta as ArchetypePolicy


# ── Sampling ──────────────────────────────────────────────────────────────


func _on_reseed_pressed() -> void:
	_rng.seed = randi()
	_update_seed_label()
	# Re-roll at the current marker so a reseed visibly changes the samples.
	if _map != null and _map.has_marker():
		_on_map_clicked(_map.marker_world())


func _update_seed_label() -> void:
	if _seed_label != null:
		_seed_label.text = "rng seed %d" % _rng.seed


func _on_map_clicked(world_pos: Vector2) -> void:
	if _config == null:
		_clear_cards(_cards, "no config")
		return
	var policy := _selected_archetype()
	for i in _SAMPLE_COUNT:
		_fill_card(_cards[i], i, _sample_once(world_pos, policy))


## One node's worth of rolls at `world_pos`: budget via BudgetPolicy, content
## via the phased v3 draw — the same two calls GraphProcgen's per-node loop
## makes. Shared by both sub-tabs — the Node Graph tab treats a node click as
## just another `world_pos` to sample, same as a Map Sample click. Stashes the
## budget roll's factor breakdown (#166) on the result so the card can show
## *why* it landed there, not just the final number.
func _sample_once(world_pos: Vector2, policy: ArchetypePolicy) -> Dictionary:
	var archetype_id: StringName = policy.id if policy != null else &""
	var budget := 0
	var breakdown := {}
	if _config.budget_policy != null:
		breakdown = _config.budget_policy.compute_budget_breakdown(archetype_id, world_pos, [], _rng)
		budget = breakdown.budget
	var sample := _sample_with_budget(world_pos, policy, budget)
	sample["breakdown"] = breakdown
	return sample


## Content draw only, for a caller that already has a `budget` in hand.
func _sample_with_budget(world_pos: Vector2, policy: ArchetypePolicy, budget: int) -> Dictionary:
	var archetype_id: StringName = policy.id if policy != null else &""
	var primary_stat: StringName = policy.primary_stat if policy != null else &""
	var forbid: Array[StringName] = policy.forbid_tags if policy != null else ([] as Array[StringName])
	var mods: Array[StatModifier] = []
	if _config != null and _config.modifier_pool_set != null:
		mods = GraphProcgen._roll_modifiers_v3(
				_config.modifier_pool_set, _config.weight_profiles,
				archetype_id, primary_stat, forbid, world_pos, 0, budget, _rng, {})
	return {"budget": budget, "mods": mods}


# ── Node Graph sub-tab ────────────────────────────────────────────────────


func _on_regenerate_graph_pressed() -> void:
	_regenerate_graph()


## Async (awaits [method NodeGraphView.generate], which awaits [method
## GraphProcgen.generate]) — fired without an `await` at the call site since
## nothing here needs the result synchronously.
##
## `reuse_seed` keeps the same layout across a live-edit refresh
## ([method refresh_from_config]) instead of reshuffling node positions on
## every keystroke; an explicit Regenerate (or the first generation) always
## rolls a fresh one.
func _regenerate_graph(reuse_seed: bool = false) -> void:
	if _config == null or _graph_view == null:
		return
	var cfg: GraphProcgenConfig = _config.duplicate(true)
	cfg.node_count = int(_graph_node_count_spin.value) if _graph_node_count_spin != null else _GRAPH_PREVIEW_NODE_COUNT
	cfg.n_random_starters = 0
	# Guaranteed placements (e.g. RandomBudgetBoost's fixed `count`) are
	# calibrated for the preset's full node_count — first_level.tres rolls a
	# fixed 10 anomalous nodes for 800, which would be ~60% of a 16-node
	# preview. That drowns the budget-field gradient this tab exists to show,
	# so the preview skips them entirely (same rationale as zeroing
	# n_random_starters above — this graph previews the field, not placements).
	cfg.guaranteed_placements = []
	cfg.seed = _last_graph_seed if reuse_seed and _last_graph_seed != 0 else randi()
	_last_graph_seed = cfg.seed
	_clear_cards(_graph_cards, "Generating…")
	await _graph_view.generate(cfg)
	_clear_cards(_graph_cards, "Click a node to sample it.")


## A node is a location, not a baked result — sample it exactly like a Map
## Sample click would at that world position.
func _on_graph_node_clicked(node: SkillNode) -> void:
	if _config == null or not is_instance_valid(node):
		return
	if _paint_mode:
		_paint_stamp_at(node)
	else:
		_sample_at_node(node)


func _sample_at_node(node: SkillNode) -> void:
	var policy := _selected_archetype()
	for i in _SAMPLE_COUNT:
		_fill_card(_graph_cards[i], i, _sample_once(node.position, policy))


func _paint_stamp_at(node: SkillNode) -> void:
	if _graph_view == null:
		return
	var arch_idx := _selected_stamp_archetype_idx()
	if arch_idx < 0:
		return
	var radius := _stamp_radius_spin.value if _stamp_radius_spin != null else 200.0
	_graph_view.paint_stamp(node.position, radius, arch_idx)
	_sample_at_node(node)


func _on_paint_mode_toggled(pressed: bool) -> void:
	_paint_mode = pressed
	if _stamp_paint_toggle != null:
		_stamp_paint_toggle.text = "Painting…" if pressed else "Paint Mode"
	if _graph_cards != null:
		_clear_cards(_graph_cards, "Painting: click a node to stamp." if pressed else "Click a node to sample it.")


func _on_clear_stamps_pressed() -> void:
	if _graph_view != null:
		_graph_view.clear_stamps()
	_clear_cards(_graph_cards, "Stamps cleared.")


func _populate_stamp_archetypes() -> void:
	if _stamp_arch_option == null:
		return
	_stamp_arch_option.clear()
	if _config == null or _config.archetypes.is_empty():
		_stamp_arch_option.add_item("(no archetypes)")
		return
	for k in _config.archetypes.size():
		var policy: ArchetypePolicy = _config.archetypes[k]
		if policy == null:
			continue
		_stamp_arch_option.add_item(String(policy.id))
		_stamp_arch_option.set_item_metadata(_stamp_arch_option.item_count - 1, k)
	if _stamp_arch_option.item_count > 0:
		_stamp_arch_option.select(0)


func _selected_stamp_archetype_idx() -> int:
	if _stamp_arch_option == null or _stamp_arch_option.selected < 0:
		return -1
	var meta = _stamp_arch_option.get_item_metadata(_stamp_arch_option.selected)
	return meta as int if meta is int else -1


# ── Cards ─────────────────────────────────────────────────────────────────


func _clear_cards(cards: Array[VBoxContainer], msg: String) -> void:
	for i in cards.size():
		_clear_card_rows(cards[i])
		if i == 0:
			var l := _make_label(msg)
			l.modulate = Color(1, 1, 1, 0.55)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cards[i].add_child(l)


func _clear_card_rows(card: VBoxContainer) -> void:
	# remove_child before queue_free so a same-frame refill doesn't briefly
	# stack the old rows (placeholder) under the new ones.
	for c in card.get_children():
		card.remove_child(c)
		c.queue_free()


func _fill_card(card: VBoxContainer, index: int, sample: Dictionary) -> void:
	_clear_card_rows(card)
	var header := _make_label("#%d · budget %d" % [index + 1, int(sample.get("budget", 0))])
	header.add_theme_font_size_override(&"font_size", 12)
	header.modulate = Color(0.85, 0.9, 1.0)
	card.add_child(header)
	var breakdown: Dictionary = sample.get("breakdown", {})
	if not breakdown.is_empty():
		var why := _make_label(_breakdown_text(breakdown))
		why.add_theme_font_size_override(&"font_size", 10)
		why.modulate = Color(1, 1, 1, 0.55)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(why)
	var sep := HSeparator.new()
	card.add_child(sep)
	var mods: Array = sample.get("mods", [])
	if mods.is_empty():
		var empty := _make_label("(nothing)")
		empty.modulate = Color(1, 1, 1, 0.45)
		card.add_child(empty)
		return
	for m in mods:
		var row := _make_label("%s %s" % [String(m.stat_id), m.contribution_text()])
		row.add_theme_font_size_override(&"font_size", 11)
		card.add_child(row)
