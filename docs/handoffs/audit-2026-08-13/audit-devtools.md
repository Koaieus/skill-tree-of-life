# Audit — first-party addons + tools/ (devtools slice)

Scope read in full: `addons/sandbox_host/` (6 .gd, 12 .tscn), `addons/spell_playground/`,
`addons/vfx_playground/`, `addons/stat_board_visualizer/`, `addons/bloom_sandbox/`,
`addons/allocation_sandbox/`, `addons/loot_sandbox/`, `addons/toast_sandbox/`,
`addons/procgen_preview/`, `tools/` (balance, blade_playground, gen_sandbox_tabs,
bake_carve_atlas). Excluded: `gut`, `godot-neovim`, `godot-git-plugin` (vendored).
Supporting reads: `scenes/dev/sandbox_world.gd`, `graph/graph.gd`,
`systems/allocation_system.gd`, `scenes/game_root.tscn`, `test/unit/test_sandbox_host_tabs.gd`,
`export_presets.cfg`, `.claude/rules/sandbox-host.md`, `docs/domain/sandbox-framework.md`.

---

### 1. LARGE | addons/spell_playground/playground_panel.gd:200 | Authored edge silently kills all 27 generated edges
**Defect:** `_build_grid_edges()` bails on `if not graph.get_edges().is_empty(): return`, and the owner's WIP self-loop (`Edge2`, authored under `Graph/Edges` in `playground_panel.tscn:1027`) is present at `_ready`, so the guard fires and the 27 code-built grid edges are never created.
**Breaks:** This *is* the owner-reported "adding one self-loop made all other edges vanish" — it is a build-guard bug in this panel, not a multimesh/instance-count bug; the graph auditor's multimesh line will not explain it, and the same trap fires for any hand-authored edge anyone adds to this tab in future.
**Fix:** Delete `_build_grid_edges()` entirely and author the 27 edges as `Edge` nodes in the `.tscn` (the owner's stated expectation, and their own TODO at `playground_panel.gd:191`), or at minimum make the guard idempotent per-pair instead of all-or-nothing.

### 2. LARGE | addons/spell_playground/playground_panel.gd:196 | Playground graph is half-authored, half-generated
**Defect:** The 16 `T_xx` SkillNodes, caster, entities and boards *are* pre-authored in the `.tscn`, but every edge is generated at `_ready` (`_build_grid_edges`) and every node position is overwritten at `_ready` (`_layout_world`), so the authored topology and the authored positions are both fiction.
**Breaks:** Answers the owner's question directly — the tab is not the static, editor-authored scene it looks like; editing a node's position or adding an edge in the editor has no effect (positions) or a destructive one (finding 1), which is exactly why the owner's `self_loops`/`Edge2` edit misbehaved.
**Fix:** Move edges into the `.tscn` and keep only a *scale* pass in `_layout_world` (or drop code layout and author absolute positions), so the scene is the single source of truth for topology and shape.

### 3. LARGE | addons/sandbox_host/tabs/*.tscn | Nine tabs on the legacy path, not six
**Defect:** `.claude/rules/sandbox-host.md` requires a live tab to instance its panel under `%PanelHost`; only `70_bloom_tab.tscn` and `18_tooltip_fan_tab.tscn` do — the other **nine** still set `panel_scene`: `10_spell`, `15_node_visuals`, `17_gimbal_3d`, `20_vfx`, `30_statboard`, `35_procgen`, `40_allocation`, `50_loot`, `60_toast`.
**Breaks:** The brief's count of six is three short (it missed `17_gimbal_3d`, `20_vfx`, `40_allocation`); every one of these tabs previews empty in the editor and takes a different code path on reload than on cold open — the divergence that cost the Bloom tab its glow pass in #371.
**Fix:** Migrate all nine (per-tab cost in finding 4), then strip the export.

### 4. MEDIUM | addons/sandbox_host/tabs/10_spell_tab.tscn:9 | Each migration is a 3-line .tscn edit, zero code
**Defect:** Migrating a tab is mechanical: delete the `panel_scene = ExtResource("2_panel")` line, add `[node name="<Panel>" parent="Layout/Split/PanelHost" index="0" instance=ExtResource("2_panel")]` + `layout_mode = 2`, optionally add the `TitleLabel` text override for a truthful editor preview — `70_bloom_tab.tscn` is the copyable template.
**Breaks:** Nothing blocks this today, which makes the nine-tab backlog pure inertia; the ordering is unchanged (`_mount_panel` adopts before `_wire_chrome`, `loader_method` still fires through `_finish_panel_setup`), and the two `Sidebar` tabs (`10_spell`, `35_procgen`) need no extra work since their sidebar overrides are independent of `%PanelHost`.
**Fix:** Do all nine in one pass; the only tab worth eyeballing afterwards is `10_spell`, whose panel `_ready` reads `world.size` (already zero-guarded and covered by `world.size_changed`).

### 5. MEDIUM | addons/sandbox_host/sandbox_live_tab.gd:147 | Dual-mode mount is dead weight post-migration
**Defect:** Once all tabs bake, `panel_scene`, `_instance_panel`, `_find_baked_panel`, the `self`-fallback branch in `_mount_panel`, the `panel_scene`-based half of `_panel_source_path`, and the whole legacy branch of `_on_panel_reload_requested` (lines 214–222) become unreachable — roughly 45 lines and five branches.
**Breaks:** Until then the script has to keep two mount semantics and two reload semantics correct, and the class docstring still tells readers the panel "is injected via `panel_scene` (DI)", teaching the wrong pattern to the next author.
**Fix:** After finding 4, delete the `panel_scene` export and all five branches, and rewrite the docstring around baking; `_panel_source_path` reduces to `_panel.scene_file_path`.

### 6. MEDIUM | tools/gen_sandbox_tabs.gd:15 | Generator docstring teaches the banned pattern
**Defect:** The "how to add a tab" instructions say a live tab overrides `tab_title / tab_id / panel_scene / loader_method` — i.e. it directs new authors straight onto the legacy path the rule forbids.
**Breaks:** This is the file an author reads when adding a tab, so the violation reproduces itself; the same goes for `test/unit/test_sandbox_host_tabs.gd:41`, which accepts `panel_scene != null or is_baked` and so exerts no migration pressure.
**Fix:** Rewrite the docstring around `%PanelHost` baking, and tighten the lint to require a baked `%PanelHost` child once finding 4 lands.

### 7. MEDIUM | tools/balance/balance_fixture.gd:76 | Third system-wiring source, already diverged
**Defect:** `BalanceFixture.build` hand-wires `AllocationSystem.new()` with only `graph` set, while `scenes/dev/sandbox_world.gd:51` also sets `navigator`, and `scenes/game_root.tscn:36` sets `navigator` *and* `turn_manager` — three parallel wiring sources, two live divergences.
**Breaks:** The fixture's whole premise is "real code paths, no reimplementation" (#268 decision 2/3), so a silent wiring gap makes it print confident numbers off a differently-wired system; the divergence is latent only because `AllocationSystem.navigator` / `.turn_manager` appear unread in that file today (worth confirming with the systems auditor), and the day one is read the harness degrades without failing.
**Fix:** Have `BalanceFixture` build its systems through `sandbox_world.gd` like the two live panels do, leaving exactly two wiring sources with the doc's stated sync obligation.

### 8. MEDIUM | tools/balance/balance_scenarios.gd:165 | Dev tooling calls Entity's private signal handlers
**Defect:** The harness drives gameplay by calling underscore-private handlers directly — `entity._on_turn_started(entity)` (`balance_scenarios.gd:165`, `:462`; `balance_fixture.gd:128`) and `entity._on_xp_replenished()` (`balance_scenarios.gd:449`, `balance_fixture.gd:82`).
**Breaks:** This is the coupling the lead asked about, and it is real: renaming or re-signaturing either handler — an ordinary refactor of `Entity`'s turn/XP wiring — breaks the balance snapshot with a runtime error, and there is no public "advance one turn of upkeep" / "grant one level" seam to call instead.
**Fix:** Add public `Entity.run_turn_upkeep()` / `Entity.grant_level()` methods that the signal handlers delegate to, and point the harness at those.

### 9. MEDIUM | addons/sandbox_host/plugin.gd:31 | Every tab is built and rendered at editor start
**Defect:** `_enter_tree` instantiates the host, whose `_register_tabs` instantiates all eleven tabs immediately — building the spell playground's 16-node graph + entities, the allocation panel's 9 entities / 9 systems-driven cells, the loot world, the bloom chart's ~200 Controls — before the Sandbox main screen has ever been shown.
**Breaks:** That cost is paid on every editor launch by everyone, including agents running headless editor passes; worse, `spell_playground`, `vfx_playground` and `bloom_sandbox` all set `render_target_update_mode = 4` (UPDATE_ALWAYS), so three SubViewports render every frame forever even while their tab is hidden and the screen is not open.
**Fix:** Lazy-instantiate a tab on first reveal (register a placeholder + `tab_changed` hook), and drop UPDATE_ALWAYS to UPDATE_WHEN_VISIBLE unless a panel demonstrably needs it.

### 10. MEDIUM | addons/spell_playground/playground_panel.gd:306 | Float readout uses %.3s and truncates as a string
**Defect:** `_format_value` renders floats with `"%.3s" % v` — a *string* precision spec applied to a number, so `12.5` prints as `12.` and `0.25` as `0.2`; `addons/vfx_playground/playground_panel.gd:88` has the same function with the correct `"%.3g"`.
**Breaks:** The spell tab's whole job is showing a SpellDef's authored values, and it silently mangles exactly the values (multi-digit damage, ramp multipliers) the owner tunes there.
**Fix:** Change to `"%.3g"`, and extract the duplicated `_build_values_text` + `_format_value` pair (~55 near-identical lines across the two panels) into one shared helper so they cannot diverge again.

### 11. MEDIUM | addons/loot_sandbox/loot_sandbox_panel.gd:115 | No shared fixture for world content, only for systems
**Defect:** `SandboxWorld` unifies *system* wiring but nothing unifies world content, so `_spawn_entity` + `_DEFAULT_BOARD.duplicate(true)` is written three times (`loot_sandbox_panel.gd:145`, `allocation_sandbox_panel.gd:142`, `balance_fixture.gd:69`), `_reset_board` twice (`loot:272`, `allocation:304`), and the `world.size_changed` → reposition → `for e in graph.get_edges(): e.refresh_endpoints()` layout idiom four times (spell, vfx, allocation, loot).
**Breaks:** Answers the lead's duplication question: yes, and it already bit — the three `Entity.new()` sites disagree on whether a `faction` and a `core_class` are set, which is the class of bug #173/#384 produced in this very panel.
**Fix:** Add a `SandboxFixture` helper (or extend `sandbox_world.gd`) with `spawn_entity()`, `make_node()`, `reset_board()` and a `relayout(graph)` that owns the `refresh_endpoints` sweep.

### 12. MEDIUM | addons/loot_sandbox/loot_sandbox_panel.gd:154 | Entities code-composed, never instanced from entity.tscn
**Defect:** Both live panels build entities with `Entity.new()` + manual property assignment instead of instancing `entity/entity.tscn`, contrary to `.claude/rules/scene-composition.md` (the same defect the brief already pre-files against `ui/tooltip_fan/fan_live_sandbox.gd`).
**Breaks:** Anything `entity.tscn` packages as a child — and the scene is what the game and the spell playground's own `.tscn` both instance — is silently absent in these two sandboxes, so a sandbox "driving the real systems" is driving them against an entity the game never produces.
**Fix:** `preload("res://entity/entity.tscn").instantiate()` in the shared spawn helper from finding 11.

### 13. MEDIUM | export_presets.cfg:8 | Release build ships every dev tool
**Defect:** `export_filter="all_resources"` with an empty `exclude_filter`, so `addons/` (including all nine sandbox panels and GUT), `tools/`, `test/` and `docs/` are packed into the release export.
**Breaks:** No dev-tool code is *reachable* from a release entry point — `Boot` swaps to `first_level_sandbox` and no shipped scene references a panel — but it all ships, bloating the `.pck` and putting the balance harness, the env-writing bloom panel and GUT one `load()` away inside the shipped build.
**Fix:** Set `exclude_filter="addons/*,tools/*,test/*,docs/*"` (keep `addons/gut` out too — the export preset is the only gate, since GUT is not autoloaded).

### 14. MEDIUM | addons/sandbox_host/sandbox_tab.gd:8 | Base-class docstring contradicts the design doc
**Defect:** The class doc says PLAYED means "a non-`@tool` gameplay scene" for "allocation / loot showcases" and that `@tool`-ing those systems is "the explicitly-rejected branch", and claims discovery is a `get_global_class_list` base scan — all three were reversed by #260 and #77 phase 4 (`sandbox_played_tab.gd` and `sandbox-framework.md` both state the corrected version).
**Breaks:** The mode distinction is the load-bearing concept of the whole framework, and the base class — the first file an author reads — states the retired version of it, so the next tab gets classified by the wrong rule.
**Fix:** Replace with the "auto-tick = played; explicit-step = live" kernel and the `tabs/` directory-scan contract.

### 15. NIT | addons/allocation_sandbox/allocation_sandbox_panel.gd:311 | Raw PoolStat base_value writes exist after all
**Defect:** `b.skill_points.base_value = sp_base` (allocation) and `b.skill_points.base_value = 20.0` (`loot_sandbox_panel.gd:279`) write a `PoolStat` base directly, which `.claude/rules/stat-knobs-and-bins.md` reserves for deliberate cap-ratchet skips.
**Breaks:** Harmless today because both immediately `set_current(...)`, but it corrects the brief's Phase-1 baseline ("zero raw `base_value =` writes outside tests") — the grep missed `addons/`, so any future sweep will believe the tree is clean when it isn't.
**Fix:** Use `set_base_ratcheted(...)` in both, or add a comment stating the skip is intended.

### 16. NIT | tools/blade_playground/playground.gd:1 | Standalone and orphaned, not coupled — hypothesis refuted
**Defect:** The 660-line blade playground imports nothing from the game (its own `node_pos`/`edges` arrays, its own verlet solver, its own damage numbers) — the suspected "reaching into game internals" coupling is simply absent, but it is also unreachable: no `tabs/*.tscn` references it, and `docs/domain/sandbox-framework.md` lists it as "stale".
**Breaks:** It is 660 lines of un-run, un-tested, un-discoverable code whose Clamp/tensegrity model is now separately implemented for real in `attack/melee/` (#405/#406), so it can silently contradict shipped behaviour while looking authoritative.
**Fix:** Either give it a `SandboxPlayedTab` launch card (the mode exists precisely for auto-driven surfaces like this) or delete it and keep the design knowledge in `docs/design/`.

### 17. NIT | tools/balance/balance_scenarios.gd:410 | Readout schema is a bare string-keyed Dictionary
**Defect:** `combat_readouts` returns an untyped `Dictionary` with ~25 string literal keys that `balance_invariants.gd`, `invariants.json` and `snapshot.md` all key off by name, with no shared constant anywhere.
**Breaks:** A typo or rename in any of the four places fails silently — the readout just vanishes from the snapshot table and the invariant reads its `.get(key, 0.0)` default — which is the worst failure mode for a tool whose output is a committed diff.
**Fix:** Hoist the key names to `const` StringNames on `BalanceScenarios` and reference them from the invariant checker.

### 18. NIT | tools/ | Worst untyped-collection density in the repo, concentrated in two files
**Defect:** 163 bare `var x = …` / `var x := …` declarations and ~80 unparameterised `Dictionary`/`Array` across `tools/` + first-party addons; `tools/blade_playground/playground.gd` alone carries ~20 (`var node_pos: Array = []  # Array[Vector2]`, `var edges: Array = []  # Array[[gi,gj]]`, `var clamped_nodes := {}`), with the element type stated only in a trailing comment.
**Breaks:** The blade playground's arrays-of-arrays index scheme (`e[0]`, `t[2]`, `blade[local_of[i]]`) is the single hardest thing to read in this slice, and none of it is type-checked, so an index-shape mistake surfaces as a wrong number rather than a parse error.
**Fix:** Type the collections (`Array[Vector2]`, `Array[Vector2i]`, `Dictionary[int, bool]`) — this alone removes most of the comment cruft.

### 19. NIT | addons/spell_playground/playground_panel.gd:221 | Single-call passthrough wrapper
**Defect:** `_add_edge(a, b)` does nothing but `graph.add_edge(a, b)`.
**Breaks:** Trivial, but it hides the fact that edge creation goes through the real `Graph` API from anyone scanning for why authored edges and generated edges collide (finding 1).
**Fix:** Inline it, or delete it along with `_build_grid_edges`.

### 20. NIT | addons/sandbox_host/sandbox_host.gd:23 | Untyped tab registry
**Defect:** `var _live_tabs: Dictionary = {}` with a comment stating `StringName -> SandboxLiveTab`, then read back through `var tab: Variant = _live_tabs.get(id)` and duck-typed calls in `route_to` / `reveal_tab` / `refresh`.
**Breaks:** A tab whose `loader_method` no longer exists, or a `tab_id` typo in a `.tscn`, fails as a silent no-op rather than an error — precisely the class of failure `test_sandbox_host_tabs.gd` was written to catch, and it does not cover it.
**Fix:** `Dictionary[StringName, SandboxLiveTab]` and typed reads.

---

## Verdict

The host framework itself is well-modelled — the mode kernel, directory discovery, scenic
base with breadcrumb chrome, and whole-tab reload are all the right shapes, and the docs
reason honestly about why the obvious refactors were rejected. What is not healthy is the
gap between that design and the tabs: nine of eleven still ride the legacy `panel_scene`
path, and the generator docstring, the base-class docstring and the lint test all still
bless it, so the migration has no pressure behind it despite costing three lines a tab.
The panels below the host are the weaker layer — three parallel system-wiring sources that
have already diverged, entity/board/layout boilerplate copy-pasted three or four ways, and
a spell playground whose "pre-authored scene" is really an `_ready` generator, which is the
actual cause of the owner's vanished-edges bug. Nothing here is wrongly *modelled*; it is a
good design that stopped being finished, twice.
