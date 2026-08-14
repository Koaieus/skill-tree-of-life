# Audit — graph core slice (`graph/`, `entity/`, `autoload/`, `scenes/`, `archetypes/`)

Scope read in full: every `.gd` in the five dirs, plus `graph/graph.tscn`,
`graph/edge.tscn`, `graph/edge_mesh.gdshader`, `graph/edge_mesh_material.tres`,
`scenes/game_root.tscn` (FogOverlay node), `scenes/dev_sandbox.tscn` +
`addons/spell_playground/playground_panel.tscn` (owner WIP diff), and the
consumers named in the brief (`ui/fog_overlay/fog_overlay.gd`, `ui/z_layers.gd`,
`test/unit/test_edge_mesh_render.gd`, `test/unit/test_edge_z_order.gd`).

---

## Part A — the three owner-reported bugs

### 1. CRITICAL | addons/spell_playground/playground_panel.gd:201 | Authored self-loop suppresses all runtime edge building
**Defect:** `_build_grid_edges()` bails with `var existing := graph.get_edges(); if not existing.is_empty(): return`, and the playground's 24 grid edges exist ONLY as runtime output of that function — at HEAD the scene authors **zero** Edge children (`grep -c 'parent=".../Graph/Edges"'` → 0; working tree → 1), so the owner's single authored self-loop `Edge2` makes `existing` non-empty and every other edge is never created.
**Breaks:** This is the whole "adding one self-loop made all other edges disappear" report — the edges did not vanish from a renderer, they were never built. It also means the panel's TODO ("THIS IS SUPPOSED TO BE A PRE-AUTHORED SCENE") is currently unimplementable: authoring *any* edge into the scene silently deletes the other 24.
**Fix:** Drop the all-or-nothing guard — skip only edges that already exist (`if graph.get_edges().any(matches(a,b)): continue` inside `_add_edge`), or finish the TODO by authoring all 24 edges into the `.tscn` and deleting `_build_grid_edges()` entirely.

**Refutation of the brief's hypothesis:** the multimesh is not implicated at all. `SkillNode.segment_between` (`skill_node/skill_node.gd:552`) returns an EMPTY array when `dist <= a.radius + b.radius`, which a self-loop (`dist == 0`) always satisfies, and `Edge._push_transform` (`graph/edge.gd:215`) early-returns on both `is_self_loop` and `seg.is_empty()`. There is no division by a zero-length direction vector, and `Graph._on_edge_added_render` (`graph/graph.gd:108`) skips self-loops before they ever reach `_register_edge_slot`, so instance count and buffer rebuild are untouched. `dev_sandbox.tscn` — which authors all its edges into the scene — gained the same kind of self-loop in the same WIP and does *not* lose its edges, which is the control case.

### 2. HIGH | graph/edge.gd:364 | Self-loop draw path uses the SDR colour function
**Defect:** `_draw_self_loop()` calls `_display_color(from.base_type_color, lit)`, whose own docstring (`graph/edge.gd:262`) says it is "SDR only"; the multimesh path calls `_display_color_lifted` (`graph/edge.gd:325`), which is the ONLY place the `pow(2, lit_glow_stops)` HDR emissive lift is applied. That single call is the exact divergence point — a lit self-loop's colour never crosses 1.0, so the shared `WorldEnvironment` glow pass (`glow_hdr_threshold`) never fires on it.
**Breaks:** A lit self-loop renders visibly dimmer than every lit regular edge touching the same node — the reported "self-loops lack the glow". It also means `lit_glow_stops` (authored 4.5 in `edge.tscn`) is silently a no-op for self-loops.
**Fix:** Call `_display_color_lifted` in `_draw_self_loop`; the raw (non-`Emissive.at()`) multiply is correct here too because `draw_arc`'s `Color` carries no `source_color` hint, exactly like `set_instance_color` — but confirm on a real opengl3 renderer, never headless, since this file's own comment at `graph/edge.gd:279-301` records that the headless path lied about precisely this.

### 3. HIGH | graph/edge.gd:113 | Sensed self-loop promotes to z 991, below fog at 1000
**Defect:** `sensed`'s setter writes `ZLayers.EDGE + ZLayers.SENSED` = `-10 + 1001` = **991**, and `FogOverlay` is authored at `z_index = 1000` (`scenes/game_root.tscn:97`). `ui/fog_overlay/fog_overlay.gd:196` repeats the same expression for the visible-self-loop branch. `SkillNode` gets away with the idiom because its band is `GRAPH_DEFAULT` (0) → 1001; the EDGE band is negative, so the same additive pattern silently lands under the fog.
**Breaks:** A sensed self-loop is painted over by the opaque fog quad — it delivers none of the "topology breadcrumb reads through fog" contract that `sensed` exists for, and a visible self-loop in the fade zone loses the same fight. Third independent way a self-loop diverges from a regular edge.
**Fix:** Promote to the absolute `ZLayers.SENSED` band (1001), not `EDGE + SENSED`; `test_edge_z_order.gd:52` only asserts the *return* value so add an assertion on the promoted value.

---

## Part B — architecture

### 4. LARGE | graph/graph.tscn:14 + graph/edge.gd:166 | Two edge render paths, not two nodes
**Defect:** The owner's `Edges`-vs-`EdgeMesh` question has a "neither" answer: `MultiMeshInstance2D` accepts children fine, so merging the nodes is cosmetic. The real duplication is two complete render pipelines for one concept — stretched-quad multimesh + `edge_mesh.gdshader` vs. per-instance `_draw_self_loop`; `_display_color_lifted` vs `_display_color`; per-fragment vision self-shading vs `FogOverlay`'s `modulate.a` + z dance; `vision_visible` vs `sensed`-writes-`z_index`. #413 scoped self-loops out and never came back (`graph/graph.gd:104`, `graph/edge.gd:17-20`).
**Breaks:** Findings 2 and 3 are both direct symptoms — every future edge visual must be implemented twice or it silently applies to only one kind of edge, and self-loops keep costing a CanvasItem + `_draw` each at a scale the repo pins at 500–2500 nodes.
**Fix:** Bring the loop's ring into the batch (a second `MultiMeshInstance2D` with a ring mesh, or an SDF branch in `edge_mesh.gdshader` keyed off a custom-data flag), after which `Edges` stops needing to be a CanvasItem parent and can be a plain `Node` container named for what it is (`EdgeModel` / `EdgeRenderer`).

### 5. MEDIUM | skill_node/skill_node.gd:137 | `self_loops` is a derived index exposed as `@export`
**Defect:** `@export var self_loops: Array[Edge]` is maintained purely at runtime (`Edge._register_self_loop`, `Graph.remove_edge:315`) yet the editor serializes it — the owner's WIP baked `self_loops = [null, NodePath("../../Edges/Edge2")]` into `playground_panel.tscn`, one real entry and one null. This contradicts the principle `graph/graph.gd:37-42` states for `_edge_slot` ("per-instance RUNTIME state, not something a `.tscn`/`@export` should carry").
**Breaks:** `self_loop_count` reads 2 for one loop, so `GraphMirror.get_degree` (`graph/graph_mirror.gd:119`) over-reports degree by +2 while `Graph._ensure_topology` (`graph/graph.gd:276`) counts it correctly — two disagreeing degree answers, feeding spell `min_degree` gating (`entity/spell_book.gd:_node_meets_source_requirements`). `_draw_self_loop`'s `find(self)` also returns 1, inflating the ring radius 40%.
**Fix:** Make `self_loops` a plain `var` rebuilt from the graph, or keep the export and have `_register_self_loop` prune nulls / dedupe on `_ready`.

### 6. MEDIUM | graph/graph_mirror.gd:127 | `get_nodes_by_degree` ignores self-loops that `get_degree` counts
**Defect:** `get_degree` adds `2 * node.self_loop_count`; `get_nodes_by_degree` reads bare `astar.get_point_connections(id).size()`. Two degree definitions inside one class, and `.claude/rules/degree.md` names `GraphMirror.get_degree` as the canonical one.
**Breaks:** `get_leaf_nodes()` → `RangedAttackPlan._gather_sources` (`attack/plan/ranged_attack_plan.gd:46`) offers a node with one edge + one self-loop (true degree 3) as a ranged-attack launch leaf, while `SpellBook`'s `min_degree` gate on the same node computes 3 — the two systems disagree about the same node in the same turn.
**Fix:** Have `get_nodes_by_degree` call `get_degree(node)` per node instead of re-deriving.

### 7. MEDIUM | graph/graph_mirror.gd:48 | `mirror_add` walks every edge in the graph, per node
**Defect:** `mirror_add` calls `graph.get_edges()` and scans all E edges to find the new node's incident ones. `wire_to` (`graph/graph_mirror.gd:87`) calls it once per node → O(N·E) at level load, and `AllocationSystem.force_allocate` (`systems/allocation_system.gd:155,186`) pays a fresh O(E) on *every single allocation*.
**Breaks:** This is the exact quadratic shape `.claude/rules/graph.md` documents twice as a shipped bug. At the pinned 2500-node scale, `procgen_play_sandbox`'s territory seeding (`enemy_territory_size = 20` × N enemies) makes each claimed node cost a full edge sweep, and `Navigator._ready`'s bootstrap is ~2500 × ~3000 iterations.
**Fix:** Use `graph.get_neighbours(node)` — the cached adjacency index — instead of scanning `get_edges()`.

### 8. MEDIUM | entity/entity.gd:159 | `EntityNavigator.new()` + `add_child` instead of a scene
**Defect:** The per-entity navigator is code-composed at runtime with its `entity`/`graph` deps assigned imperatively, directly against `.claude/rules/scene-composition.md`. Same pattern at `scenes/game_root.gd:213-219` (`_ensure_controllers`) and `scenes/game_root.gd:264` (`AIController.new()` in `spawn_entity`).
**Breaks:** `entity.tscn` does not ship pre-packaged with the child every `Entity` unconditionally needs, so the node is invisible in the editor, can't be inspected or per-entity tuned, and a scene author cannot swap the navigator for a variant without editing `entity.gd`.
**Fix:** Bake `EntityNavigator` into `entity.tscn` with an exported NodePath to the graph (or a `_ready` bind), and instance controller scenes rather than `.new()`.

### 9. MEDIUM | graph/edge.gd:216 | Overlapping endpoints leave a stale multimesh transform
**Defect:** `_push_transform` returns on `seg.is_empty()` without touching the slot, so an edge whose endpoints drift within `radius_a + radius_b` keeps whatever transform it last had.
**Breaks:** The quad freezes at its previous position instead of collapsing or hiding — a floating orphan segment during any layout/core-move that brings two nodes close. `refresh_endpoints()` cannot recover it either.
**Fix:** On empty segment, write a zero-length transform (or set the slot's vis-state to `VIS_HIDDEN`) rather than returning.

### 10. MEDIUM | scenes/game_root.gd:233 | `if false: await` workaround baked into the public subclass seam
**Defect:** `_setup_level()`'s body opens with `if false: await get_tree().process_frame  # include fake await to make godot see this as a coroutine`.
**Breaks:** Every subclass author must know that overriding this hook synchronously is fine only because of a dead statement in the base — the seam's async contract is carried by a language trick, not by a signature. Delete the line and `procgen_play_sandbox.gd`'s `await _setup_level()` silently stops awaiting.
**Fix:** Document the coroutine contract on the method and keep the line with a `## @coroutine`-style docstring note, or restructure so the base returns a `Signal`/`Awaitable` explicitly.

### 11. MEDIUM | autoload/scene_loader.gd:1 | Confirmed: zero callers, still autoloaded
**Defect:** Grep over all `.gd`/`.tscn`/`.godot` finds `SceneLoader` only in `project.godot:25` and its own `.tscn` — issue #212's claim holds. `SceneTransition` (its natural partner) is used, but only by `procgen_play_sandbox.gd`, which drives its progress bar by hand rather than through the loader.
**Breaks:** A permanently-resident autoload with `_process` machinery, an `assert`-based single-flight guard, and no consumer — dead weight in every scene, and the abstraction has drifted from what level loading actually does.
**Fix:** Either wire `procgen_play_sandbox`'s manual `SceneTransition` progress dance through it, or delete both the autoload entry and the file per #212.

### 12. MEDIUM | archetypes/archetype.gd:24 | `color` getter dereferences an unguarded registry lookup
**Defect:** `get: return StatRegistry.get_def(primary_stat).tint_color` — `get_def` returns `null` for an unregistered id, and `Archetype.primary_stat` is explicitly documented as free-form ("any `StatRegistry` id", not restricted to the six attributes).
**Breaks:** A typo'd or not-yet-authored `primary_stat` crashes on a property *read* from a `@tool` script — so it takes the editor down while inspecting the resource, with no hint that the id is the problem.
**Fix:** `var def := StatRegistry.get_def(primary_stat); return def.tint_color if def != null else Color.MAGENTA` plus a `push_warning`.

### 13. LOW | graph/graph_mirror.gd:20 | Three mirrors is the right count; the naming is not
**Defect:** `Navigator` (auto, mirrors all), `EntityNavigator` (auto, mirrors owned), and the manual plan-driven mirror (`attack/plan/melee_attack_plan.gd:273`) are three *instances* of one `GraphMirror` abstraction with a single `_should_mirror` hook — that is correct modelling, not duplication, and `.claude/rules/graph.md` depends on the divergence being real (owned-subgraph reach must not shortcut through enemy land). But `Navigator`/`EntityNavigator` names describe pathfinding while the class is a topology mirror whose main users ask connectivity questions.
**Breaks:** Nothing today; it costs a reader one indirection to learn that `entity.navigator` is "my induced subgraph", not "my pathfinder".
**Fix:** Consider `GlobalGraphMirror` / `OwnedGraphMirror`; low priority, rename-only.

### 14. LOW | entity/core/core_class.gd:1 | `CoreClass` is a real abstraction, thinly used
**Defect:** It is genuinely more than a config bag — `apply()` and `on_turn_started()` are overridable, and `Entity` composes rather than extends (`entity/entity.gd:33`), which matches the composition-over-inheritance house rule. But every shipped `.tres` rides the plain base; not one subclass exists, so the virtual hooks are unexercised.
**Breaks:** Nothing broken; the `aura` field is applied by `Entity._on_turn_started` (`entity/entity.gd:310-318`) rather than by the class itself, which is the one place the seam leaks — Entity knows about `CoreAura` specifically.
**Fix:** Move the aura sweep into `CoreClass.on_turn_started`'s default body so `Entity` only dispatches, and the class owns everything class-shaped.

### 15. LOW | entity/entity.gd:296 | `_on_turn_started` mixes upkeep, aura math, and dispatch
**Defect:** One 26-line function does pool upkeep, resolves the class aura, sweeps every owned node for regen, applies aura values, calls the class hook, and dispatches an effect hook.
**Breaks:** The owned-node sweep is the per-turn hot loop (up to a few hundred nodes) and is entangled with aura resolution, so neither can be tested or optimised without the other.
**Fix:** Extract `_run_owned_node_upkeep()` covering the aura + regen loop.

### 16. LOW | autoload/scene_transition.gd:1 | Autoload predating the repo's own conventions
**Defect:** No return types on `fade_out`/`fade_in`/`_ready`, deprecated `emit_signal("...")` string form (three sites), a commented-out `class_name`, and `set_faded` shows the layer as a side effect of a setter-shaped name.
**Breaks:** `procgen_play_sandbox.gd:81-84` has to reach through to `SceneTransition.progress_bar.show()` because the API doesn't cover "show progress without animating a fade" — the caller is patching around the missing verb.
**Fix:** Add return types, use `signal.emit()`, and give it a `begin_progress()` verb the sandbox can call.

### 17. LOW | autoload/boot.gd:12 | Release entry point resolves its config by untyped string
**Defect:** `first_level_sandbox.get('preset') as GraphProcgenConfig` — a stringly-typed property fetch on a `GameRoot` that may not declare `preset` (only `ProcgenPlaySandbox` does), plus an unchecked `as GameRoot` cast.
**Breaks:** Renaming `preset` breaks the release build only, silently (the `if procgen_config:` guard swallows it) — the one configuration nobody runs in the editor.
**Fix:** Type the local as `ProcgenPlaySandbox` and set `preset.seed` directly, or add a `set_boot_seed(int)` method on `GameRoot`.

### 18. NIT | autoload/events.gd:1 | No dead signals — hypothesis refuted
**Defect:** All 20 bus signals have at least one non-test production `connect` site (counts range 1–11). The brief's "check `Events` for signals nobody listens to" finds nothing.
**Breaks:** n/a — recording the refutation so it isn't re-derived.
**Fix:** None. The one soft spot is `ai_decision` (`autoload/events.gd:107`), documented as "zero consumers is a no-op" but actually having 2 — the docstring is stale.

### 19. NIT | graph/graph.gd:302 | `const EDGE` declared mid-file between two functions
**Defect:** `const EDGE = preload("res://graph/edge.tscn")` sits at line 302, between `remove_skill_node` and `add_edge`, untyped and screaming-case-but-not-grouped with the other constants.
**Breaks:** Constants are otherwise all at the top of the file; a reader scanning the header sees no scene dependency.
**Fix:** Move it up with the other declarations and type it `: PackedScene`.

### 20. NIT | scenes/addon_tile.gd:22 | Procedural addon composition inside a scene-authored tile
**Defect:** The docstring says "Scene-authored (was procedural node composition)", but `configure` still does `Node2D.new()` + `set_script(addon_script)` + `add_child`.
**Breaks:** The comment claims a migration that only half happened; an addon whose scene packages children (as the sandbox-host rule warns) previews empty in the gallery.
**Fix:** Take a `PackedScene` per addon and `instantiate()`, or amend the docstring to say only the tile chrome is scene-authored.

### 21. NIT | scenes/game_root.gd:270 | `_on_core_moved` is never connected
**Defect:** The method exists with a three-arg signature matching the `_on_core_moved` effect hook that `Entity.core_location`'s setter dispatches (`entity/entity.gd:68`), but `GameRoot` is not an `Effect` and nothing ever calls it — grep finds no `_on_core_moved` connection or `dispatch` target on GameRoot.
**Breaks:** Dead code shaped exactly like a live hook, so a reader assumes core-move slide VFX are wired here when they are not.
**Fix:** Delete it, or wire it to `AllocationSystem`'s core-move path if the slide VFX is meant to fire.

---

## Verdict

The domain modelling is sound: `Graph` is honestly pure topology, `GraphMirror`'s
three instantiations are one abstraction with a real hook rather than three
copies, and `CoreClass`/`Faction` composition is the right shape. What is wrong
is a **half-finished migration**: #413 moved regular edges to a batched multimesh
and explicitly left self-loops on the old `_draw` + z-index + `modulate` path,
and all three of the owner's render complaints are that seam (findings 2, 3, 4) —
`Edges` vs `EdgeMesh` is the visible symptom of two pipelines, not two nodes. The
third reported bug is unrelated to rendering entirely: a defensive early-return in
`playground_panel.gd` means authoring any edge into that scene deletes the other
24. Beyond the bugs, the recurring weakness is derived state that escapes its
owner — `self_loops` serialized into `.tscn`s, two disagreeing degree answers in
`GraphMirror`, and an O(E)-per-allocation `mirror_add` that walks straight into
the quadratic trap `.claude/rules/graph.md` already documents twice.
