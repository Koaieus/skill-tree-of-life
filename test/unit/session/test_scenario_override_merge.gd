extends GutTest

## #642 (child 2 of #597) — the module-override merge path. Covers the body's
## acceptance 1/2/3/4/7 (the LobbyPolicy-facing 5/6 belong to #643's UI wave,
## out of this drone's scope), the "VERIFIED against the engine" comment's
## acceptance 8/10, and the "Hardening D14" comment's D15 + acceptance 11 —
## the three ways `set_indexed` fails SILENTLY (typed-array target,
## wrong-type value, lossy float-into-int) each get their own test asserting
## the preset is UNCHANGED, not merely that a warning fired.

const _COOP_VERSUS_PRESET_PATH := "res://procgen/presets/coop_versus/coop_versus.tres"
const _COOP_VERSUS_CONTENT_PATH := "res://procgen/modules/coop_versus/content.tres"
const _COOP_VERSUS_SCENARIO_PATH := "res://session/scenarios/coop_versus.tres"


func _fresh_preset() -> GraphProcgenConfig:
	# `load` is cached; every test gets its own top-level duplicate so a
	# forgotten mutation in one test can't bleed into the next (same
	# discipline as `test_coop_versus_preset.gd`'s `_fresh_config`).
	return (load(_COOP_VERSUS_PRESET_PATH) as GraphProcgenConfig).duplicate(true)


func _generate(cfg: GraphProcgenConfig) -> Array:
	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	var result: Dictionary = await GraphProcgen.generate(cfg, graph)
	return result.get("nodes", [])


func _override(target: String, value: Variant) -> ScenarioOverride:
	var o := ScenarioOverride.new()
	o.target = target
	o.value = value
	return o


# ── Acceptance 1 — an override changes the generated map ───────────────────


func test_a_topology_override_generates_the_overridden_node_count() -> void:
	var preset := _fresh_preset()
	var authored_node_count: int = preset.topology.node_count
	var overrides: Array[ScenarioOverride] = [_override("topology:node_count", 60)]

	var cfg := ScenarioOverride.merge_onto(preset, overrides)
	cfg.seed = 4242
	var nodes := await _generate(cfg)

	assert_ne(authored_node_count, 60, "sanity: the override must differ from the authored value")
	assert_true(nodes.size() <= 60 and nodes.size() > 20,
			"expected close to the overridden 60, got %d (authored preset asks for %d)"
			% [nodes.size(), authored_node_count])


# ── Acceptance 2 — no override reproduces the authored map exactly ─────────


func test_no_overrides_reproduces_the_authored_map_byte_for_byte() -> void:
	var seed_value := 20260827

	var direct: GraphProcgenConfig = _fresh_preset()
	direct.topology = direct.topology.duplicate(true)
	direct.topology.node_count = 40
	direct.seed = seed_value
	var direct_nodes := await _generate(direct)

	var merged := ScenarioOverride.merge_onto(_fresh_preset(), [])
	merged.topology = merged.topology.duplicate(true)
	merged.topology.node_count = 40
	merged.seed = seed_value
	var merged_nodes := await _generate(merged)

	assert_eq(merged_nodes.size(), direct_nodes.size(), "same seed, same preset, same node count")
	for i in direct_nodes.size():
		assert_eq((merged_nodes[i] as Node2D).position, (direct_nodes[i] as Node2D).position,
				"node %d position must match — merging zero overrides changes nothing" % i)


# ── Acceptance 3 (restated by "Decision — the override encoder") ───────────


## The single most important assertion in this unit: a `RunConfig` carrying
## overrides for all four LAN knobs — including the two that reach into a
## sub-resource — survives `to_dict()` -> `from_dict()` with every target and
## value intact, with NO `resource_path` involved anywhere in an override
## (#597 D4's silent-`""` failure mode, made unreachable by construction), and
## a client generating from the DECODED config produces a map identical to
## the host's.
func test_all_four_lan_knobs_survive_the_wire_and_the_client_matches_the_host() -> void:
	var source := RunConfig.new()
	source.scenario = load(_COOP_VERSUS_SCENARIO_PATH) as Scenario
	source.seed = 990011
	source.overrides = [
		_override("topology:node_count", 60),           # map size — one hop
		_override("blockers:blocker_per_small", 7),      # blocker density — one hop
		_override("starting:starter_placement:arrangement", 2),  # RANDOM — two hops
		_override("content:budget_policy:base_min", 3),  # "go HAM" — two hops
	]

	var dict := source.to_dict()
	assert_true(dict.has("overrides"), "overrides must be on the wire")
	for row in (dict["overrides"] as Array):
		var r := row as Dictionary
		assert_false(r.has("resource_path"),
				"an override's wire row must carry no resource_path anywhere — #597 D4")

	var decoded := RunConfig.from_dict(dict)
	assert_eq(decoded.overrides.size(), source.overrides.size())
	for i in source.overrides.size():
		assert_eq(decoded.overrides[i].target, source.overrides[i].target, "target %d" % i)
		assert_eq(decoded.overrides[i].value, source.overrides[i].value, "value %d" % i)

	var host_cfg := source.resolved_preset()
	host_cfg.seed = source.seed
	var client_cfg := decoded.resolved_preset()
	client_cfg.seed = decoded.seed

	var host_nodes := await _generate(host_cfg)
	var client_nodes := await _generate(client_cfg)

	assert_eq(client_nodes.size(), host_nodes.size(), "same seed, same merged preset, same node count")
	for i in host_nodes.size():
		assert_eq((client_nodes[i] as Node2D).position, (host_nodes[i] as Node2D).position,
				"node %d position must match between host and client" % i)


# ── Acceptance 4 — the authored asset (and every module it references)
# is never mutated by the merge ─────────────────────────────────────────────


func test_authored_content_module_is_never_mutated_across_two_generations() -> void:
	var authored: GraphProcgenContent = load(_COOP_VERSUS_CONTENT_PATH)
	var authored_base_min: int = authored.budget_policy.base_min

	for override_value in [11, 22]:
		var cfg := ScenarioOverride.merge_onto(
				_fresh_preset(), [_override("content:budget_policy:base_min", override_value)])
		cfg.seed = 7
		await _generate(cfg)

		var reloaded: GraphProcgenContent = ResourceLoader.load(
				_COOP_VERSUS_CONTENT_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
		assert_eq(reloaded.budget_policy.base_min, authored_base_min,
				"override %d must not leak into the on-disk content module (still cached at %d?)"
				% [override_value, authored.budget_policy.base_min])
	assert_eq(authored.budget_policy.base_min, authored_base_min,
			"the live cached module read at the top of this test must also be untouched")


# ── Acceptance 7/9 — runtime-stamped fields are never overridable ──────────


func test_runtime_stamped_fields_are_rejected_as_override_targets() -> void:
	for field_name in ["seed", "camp_sizes", "n_random_starters", "viability_radius"]:
		var preset := _fresh_preset()
		var authored_node_count := preset.topology.node_count
		var cfg := ScenarioOverride.merge_onto(preset, [_override(field_name, 999)])
		assert_push_warning(field_name)
		assert_eq(cfg.topology.node_count, authored_node_count,
				"'%s' must be rejected — the preset must be otherwise unchanged" % field_name)


# ── Acceptance 8/10 — an unresolvable target warns, never a silent no-op ───


func test_an_unresolvable_target_warns_and_does_not_mutate_the_preset() -> void:
	var preset := _fresh_preset()
	var authored_node_count := preset.topology.node_count
	var cfg := ScenarioOverride.merge_onto(preset, [_override("nope:not_here", 5)])
	assert_push_warning("nope:not_here")
	assert_eq(cfg.topology.node_count, authored_node_count, "an unresolvable target must change nothing")


## Pins `get_indexed`/`set_indexed`'s own cross-Resource-hop traversal against
## the real, shipped preset — so a future engine upgrade that changes subname
## traversal fails loudly HERE rather than silently mis-merging every run
## (the "D14 VERIFIED against the engine" comment's own probe, turned into an
## assertion).
func test_set_indexed_get_indexed_traversal_is_pinned_against_the_real_preset() -> void:
	var cfg := _fresh_preset()

	assert_eq(cfg.get_indexed("content:budget_policy:base_min"), 2,
			"coop_versus's base_min is unauthored — reads the BudgetPolicy class default")
	cfg.set_indexed("content:budget_policy:base_min", 12345)
	assert_eq(cfg.get_indexed("content:budget_policy:base_min"), 12345, "write must land, two hops deep")

	assert_eq(cfg.get_indexed("starting:starter_placement:arrangement"),
			CampAnnulusStarters.Arrangement.GROUPED, "coop_versus authors GROUPED")
	cfg.set_indexed("starting:starter_placement:arrangement", CampAnnulusStarters.Arrangement.RANDOM)
	assert_eq(cfg.get_indexed("starting:starter_placement:arrangement"),
			CampAnnulusStarters.Arrangement.RANDOM, "write must land, two hops deep")

	assert_null(cfg.get_indexed("nope:not_here"), "an unresolvable path returns null, silently — the trap acceptance 8 guards")


# ── Acceptance 11 (Hardening D14) — the three silent failure modes ─────────


## 11.1 — a target resolving to a typed ARRAY is rejected, never merged.
func test_a_typed_array_target_is_rejected_and_the_preset_is_unmodified() -> void:
	var preset := _fresh_preset()
	var authored_profiles := preset.content.weight_profiles.duplicate()
	var cfg := ScenarioOverride.merge_onto(preset, [_override("content:weight_profiles", [])])
	assert_push_warning("content:weight_profiles")
	assert_eq(cfg.content.weight_profiles, authored_profiles,
			"an array target must be rejected — the preset must be unchanged, not emptied")


## 11.2 — a value whose type doesn't match the target's declared type is
## rejected; the preset keeps its authored value.
func test_a_type_mismatched_value_is_rejected_and_the_preset_keeps_its_authored_value() -> void:
	var preset := _fresh_preset()
	var authored: int = preset.starting.starter_placement.arrangement
	var cfg := ScenarioOverride.merge_onto(
			preset, [_override("starting:starter_placement:arrangement", "banana")])
	assert_push_warning("starting:starter_placement:arrangement")
	assert_eq(cfg.starting.starter_placement.arrangement, authored,
			"a String written to an int/enum leaf must be rejected outright")


## 11.3 — a float written to an int leaf lands as an EXPLICIT, documented
## rounding (never a silent truncation), and warns when that rounding is lossy.
func test_a_float_into_an_int_target_rounds_explicitly_and_warns_when_lossy() -> void:
	var lossy_cfg := ScenarioOverride.merge_onto(
			_fresh_preset(), [_override("content:budget_policy:base_min", 1.7)])
	assert_push_warning("content:budget_policy:base_min")
	assert_eq(lossy_cfg.content.budget_policy.base_min, 2,
			"1.7 must round to 2 (nearest), never truncate to 1")

	# A whole-number float is not lossy — no warning, still lands as an int.
	var clean_cfg := ScenarioOverride.merge_onto(
			_fresh_preset(), [_override("content:budget_policy:base_min", 4.0)])
	assert_eq(clean_cfg.content.budget_policy.base_min, 4)


# ── ScenarioOverride's own structural check ─────────────────────────────────


func test_an_empty_target_is_flagged_as_a_configuration_warning() -> void:
	var o := ScenarioOverride.new()
	assert_true(o._get_configuration_warnings().size() > 0, "an empty target patches nothing — warn in the inspector")

	o.target = "topology:node_count"
	assert_eq(o._get_configuration_warnings().size(), 0, "a non-empty target has no structural complaint")


func test_an_empty_target_at_merge_time_warns_and_changes_nothing() -> void:
	var preset := _fresh_preset()
	var authored_node_count := preset.topology.node_count
	var cfg := ScenarioOverride.merge_onto(preset, [_override("", 5)])
	assert_push_warning("empty target")
	assert_eq(cfg.topology.node_count, authored_node_count)
