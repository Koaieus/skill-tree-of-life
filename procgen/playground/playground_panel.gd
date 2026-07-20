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
const _ProcgenCard := preload("res://procgen/playground/procgen_card.tscn")
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

@onready var _bound_label: Label = %BoundLabel
@onready var _arch_option: OptionButton = %ArchOption
@onready var _seed_label: Label = %SeedLabel

@onready var _map: Control = %Map
@onready var _cards_row: HBoxContainer = %CardsRow
var _cards: Array[ProcgenCard] = []

@onready var _graph_view: Control = %GraphView
@onready var _graph_node_count_spin: SpinBox = %GraphNodeCountSpin
@onready var _graph_cards_row: HBoxContainer = %GraphCardsRow
var _graph_cards: Array[ProcgenCard] = []

# Stamp controls (#166)
@onready var _stamp_paint_toggle: Button = %StampPaintToggle
@onready var _stamp_arch_option: OptionButton = %StampArchOption
@onready var _stamp_radius_spin: SpinBox = %StampRadiusSpin
@onready var _stamp_clear_btn: Button = %StampClearButton
var _paint_mode := false


func _ready() -> void:
	%CardsLabel.text = "%d samples at the clicked spot:" % _SAMPLE_COUNT
	%GraphCardsLabel.text = "%d samples for the clicked node:" % _SAMPLE_COUNT
	_cards = _spawn_cards(_cards_row)
	_graph_cards = _spawn_cards(_graph_cards_row)
	_clear_cards(_cards, "Click the map to roll.")
	_clear_cards(_graph_cards, "Regenerate, then click a node.")
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


## Instantiates [constant _ProcgenCard] `_SAMPLE_COUNT` times into `row` — the
## one piece of "UI construction" that legitimately stays in code, since the
## repeat count is a const rather than authored structure. Everything static
## (labels, buttons, the map/graph views) lives in the scene now (#264).
func _spawn_cards(row: HBoxContainer) -> Array[ProcgenCard]:
	var cards: Array[ProcgenCard] = []
	for i in _SAMPLE_COUNT:
		var card: ProcgenCard = _ProcgenCard.instantiate()
		row.add_child(card)
		cards.append(card)
	return cards


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


## Matches the previous per-tab behaviour: only card slot 0 shows the
## placeholder message, the rest just go blank — a [ProcgenCard] cleared via
## [method ProcgenCard.clear] with no rows added.
func _clear_cards(cards: Array[ProcgenCard], msg: String) -> void:
	for i in cards.size():
		if i == 0:
			cards[i].show_placeholder(msg)
		else:
			cards[i].clear()


func _fill_card(card: ProcgenCard, index: int, sample: Dictionary) -> void:
	var breakdown: Dictionary = sample.get("breakdown", {})
	var breakdown_text := _breakdown_text(breakdown) if not breakdown.is_empty() else ""
	card.fill(index, sample, breakdown_text)
