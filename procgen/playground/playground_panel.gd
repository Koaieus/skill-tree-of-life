@tool
extends Control
## Procgen playground panel (#166) — a live-edit sandbox tab for tuning what
## procgen rolls, without booting a level.
##
## Sub-tab "Map Sample": renders a [GraphProcgenConfig]'s budget-field heatmap
## ([FieldMapView]); clicking a spot rolls a batch of independent draws there
## (budget via [BudgetPolicy] + content via the phased v3 draw) and lays them
## out as cards, so a designer gets an at-a-glance feel of what a node in that
## territory tends to roll. Pick the archetype to sample as from the dropdown.
##
## Sub-tab "Node Graph": generates a small preview graph via [GraphProcgen] on
## a private [Graph] and renders it via [NodeGraphView] — nodes heat-coloured
## by rolled budget (RED HOT = high), archetype-colour ring, hover tooltip
## (budget + this graph's min/max + the policy's base range), click rolls the
## same 5-card sample at that node's already-rolled budget (fixed, not
## resampled) so a RED HOT node visibly draws richer content.
##
## Composable field overlay (#162) — painting composed ScalarFields over
## either sub-tab — lands after #162's fields exist; not started.
##
## Self-contained: defaults to a duplicated `first_level.tres` so it works with
## nothing inspected. `load_config` (the SandboxLiveTab loader hook) swaps in a
## different config when one is routed from the inspector.

const _DEFAULT_PRESET := preload("res://procgen/presets/first_level/first_level.tres")
const _FieldMapView := preload("res://procgen/playground/field_map_view.gd")
const _NodeGraphView := preload("res://procgen/playground/node_graph_view.gd")

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
var _rng := RandomNumberGenerator.new()

var _arch_option: OptionButton
var _map: Control
var _cards_row: HBoxContainer
var _cards: Array[VBoxContainer] = []
var _seed_label: Label

var _graph_view: Control
var _graph_node_count_spin: SpinBox
var _graph_cards_row: HBoxContainer
var _graph_cards: Array[VBoxContainer] = []


func _ready() -> void:
	_build_ui()
	_set_config(_DEFAULT_PRESET.duplicate(true))


# ── SandboxLiveTab loader hook ────────────────────────────────────────────


## Swap in an inspected config (duplicated so we never mutate the on-disk
## resource). No-op for anything that isn't a GraphProcgenConfig.
func load_config(obj: Object) -> void:
	if obj is GraphProcgenConfig:
		_set_config((obj as GraphProcgenConfig).duplicate(true))


# ── UI ────────────────────────────────────────────────────────────────────


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var tabs := TabContainer.new()
	tabs.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(tabs)

	var map_tab := _build_map_tab()
	tabs.add_child(map_tab)
	tabs.set_tab_title(map_tab.get_index(), "Map Sample")

	var graph_tab := _build_graph_tab()
	tabs.add_child(graph_tab)
	tabs.set_tab_title(graph_tab.get_index(), "Node Graph")


func _build_map_tab() -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.add_theme_constant_override(&"separation", 6)

	# Control bar.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override(&"separation", 10)
	tab.add_child(bar)

	bar.add_child(_make_label("Sample as:"))
	_arch_option = OptionButton.new()
	_arch_option.custom_minimum_size = Vector2(160, 0)
	bar.add_child(_arch_option)

	var reseed := Button.new()
	reseed.text = "Reseed"
	reseed.pressed.connect(_on_reseed_pressed)
	bar.add_child(reseed)

	_seed_label = _make_label("")
	_seed_label.modulate = Color(1, 1, 1, 0.6)
	bar.add_child(_seed_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	bar.add_child(spacer)

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
	var cards_label := _make_label("%d samples for the clicked node (fixed budget):" % _SAMPLE_COUNT)
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


# ── Config ────────────────────────────────────────────────────────────────


func _set_config(cfg: GraphProcgenConfig) -> void:
	_config = cfg
	# Resolve any opted-in radial field radius (outer_radius <= 0) from the
	# shape, exactly as GraphProcgen does before sampling.
	if _config != null:
		GraphProcgen._propagate_mask_radius(_config)
	_populate_archetypes()
	if _map != null:
		_map.set_config(_config)
	_update_seed_label()
	_clear_cards(_cards, "Click the map to roll.")
	_regenerate_graph()


func _populate_archetypes() -> void:
	if _arch_option == null:
		return
	_arch_option.clear()
	_arch_option.add_item("Any / none")  # id 0 → sample with no archetype
	_arch_option.set_item_metadata(0, null)
	if _config == null:
		return
	for policy in _config.archetypes:
		if policy == null:
			continue
		var idx := _arch_option.item_count
		_arch_option.add_item(String(policy.id))
		_arch_option.set_item_metadata(idx, policy)
	# Default to the first real archetype if there is one — a bare "none" sample
	# only ever draws off-attribute/defensive/rare content, which reads oddly.
	if _arch_option.item_count > 1:
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
## via the phased v3 draw — the same two calls GraphProcgen's per-node loop makes.
func _sample_once(world_pos: Vector2, policy: ArchetypePolicy) -> Dictionary:
	var archetype_id: StringName = policy.id if policy != null else &""
	var primary_stat: StringName = policy.primary_stat if policy != null else &""
	var forbid: Array[StringName] = policy.forbid_tags if policy != null else ([] as Array[StringName])
	var budget := 0
	if _config.budget_policy != null:
		budget = _config.budget_policy.compute_budget(archetype_id, world_pos, [], _rng)
	return _sample_with_budget(world_pos, policy, budget)


## Same content draw as [method _sample_once], but `budget` is fixed rather
## than rolled — used by the Node Graph tab so a click samples *that node's*
## already-rolled budget instead of a fresh one (so a RED HOT node visibly
## draws richer content).
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


func _find_archetype(id: StringName) -> ArchetypePolicy:
	if _config == null or id == &"":
		return null
	for policy in _config.archetypes:
		if policy != null and policy.id == id:
			return policy
	return null


# ── Node Graph sub-tab ────────────────────────────────────────────────────


func _on_regenerate_graph_pressed() -> void:
	_regenerate_graph()


## Async (awaits [method NodeGraphView.generate], which awaits [method
## GraphProcgen.generate]) — fired without an `await` at the call site since
## nothing here needs the result synchronously.
func _regenerate_graph() -> void:
	if _config == null or _graph_view == null:
		return
	var cfg: GraphProcgenConfig = _config.duplicate(true)
	cfg.node_count = int(_graph_node_count_spin.value) if _graph_node_count_spin != null else _GRAPH_PREVIEW_NODE_COUNT
	cfg.n_random_starters = 0
	cfg.seed = randi()
	_clear_cards(_graph_cards, "Generating…")
	await _graph_view.generate(cfg)
	_clear_cards(_graph_cards, "Click a node to sample it.")


func _on_graph_node_clicked(node: SkillNode) -> void:
	if _config == null or not is_instance_valid(node):
		return
	var fp: Dictionary = node.get_meta("procgen_footprint", {})
	var budget: int = fp.get("budget", 0)
	var archetype_id: StringName = node.get_meta("base_type", &"")
	var policy := _find_archetype(archetype_id)
	for i in _SAMPLE_COUNT:
		_fill_card(_graph_cards[i], i, _sample_with_budget(node.position, policy, budget))


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
